//! Telnet for a terminal, the client's side (RFC 854), without I/O: bytes
//! from the server go in and come out as what the screen shows and what to
//! answer; what is typed goes in and comes out ready to send.
//!
//! The options a terminal needs, negotiated as RFC 1143 says so that no
//! two ends ever answer each other in a loop:
//! - the server's: ECHO (857, it echoes what is typed), SUPPRESS-GO-AHEAD
//!   (858) and BINARY (856);
//! - ours: NAWS (1073, the window's size, sent again when it changes),
//!   TERMINAL-TYPE (1091), SUPPRESS-GO-AHEAD and BINARY.
//!
//! Every other option is refused. Telnet does not encrypt: what is typed,
//! passwords too, crosses the network as it is.

/// Interpret As Command: what starts every command.
const IAC: u8 = 255;
const DONT: u8 = 254;
const DO: u8 = 253;
const WONT: u8 = 252;
const WILL: u8 = 251;
const SB: u8 = 250;
const SE: u8 = 240;

const BINARY: u8 = 0;
const ECHO: u8 = 1;
const SGA: u8 = 3;
const TTYPE: u8 = 24;
const NAWS: u8 = 31;

/// TERMINAL-TYPE's subcommands.
const IS: u8 = 0;
const SEND: u8 = 1;

const CR: u8 = b'\r';
const LF: u8 = b'\n';
const NUL: u8 = 0;

/// A subnegotiation longer than this is not one we read: it is dropped.
const MAX_SB: usize = 1024;

/// Where an option stands on one side (RFC 1143, without the queue bit:
/// we never change our mind halfway).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum Q {
    #[default]
    No,
    Yes,
    /// We asked for it and wait for the answer.
    WantYes,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Parse {
    Data,
    Iac,
    /// After `IAC` and one of WILL, WONT, DO or DONT.
    Verb(u8),
    /// Inside `IAC SB`, gathering until `IAC SE`.
    Sub,
    SubIac,
}

/// What a chunk from the server turns into.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Received {
    /// For the screen.
    pub data: Vec<u8>,
    /// For the server: answers to its negotiation.
    pub reply: Vec<u8>,
}

/// One connection's Telnet state.
#[derive(Clone, Debug)]
pub struct Telnet {
    term: String,
    size: (u16, u16),
    /// Options on our side (we WILL), by number.
    us: [Q; 256],
    /// Options on the server's side (it WILL, we DO).
    him: [Q; 256],
    parse: Parse,
    sub: Vec<u8>,
    /// The last data byte was a CR: a NUL after it is padding.
    after_cr: bool,
}

impl Telnet {
    /// For a terminal of type `term` (`xterm-256color`) and this size.
    pub fn new(term: &str, cols: u16, rows: u16) -> Self {
        Self {
            term: term.to_owned(),
            size: (cols, rows),
            us: [Q::No; 256],
            him: [Q::No; 256],
            parse: Parse::Data,
            sub: Vec::new(),
            after_cr: false,
        }
    }

    /// What to send as soon as the connection is up: the options we want,
    /// so that a server that waits for the client gets them too.
    pub fn start(&mut self) -> Vec<u8> {
        let mut out = Vec::new();
        for opt in [NAWS, TTYPE, SGA] {
            self.us[usize::from(opt)] = Q::WantYes;
            out.extend([IAC, WILL, opt]);
        }
        for opt in [SGA, ECHO] {
            self.him[usize::from(opt)] = Q::WantYes;
            out.extend([IAC, DO, opt]);
        }
        out
    }

    /// The server echoes what is typed (it WILL ECHO).
    pub fn server_echoes(&self) -> bool {
        self.him[usize::from(ECHO)] == Q::Yes
    }

    /// Bytes from the server.
    pub fn receive(&mut self, bytes: &[u8]) -> Received {
        let mut r = Received::default();
        for &b in bytes {
            match self.parse {
                Parse::Data => {
                    if b == IAC {
                        self.parse = Parse::Iac;
                    } else {
                        self.data(b, &mut r.data);
                    }
                }
                Parse::Iac => {
                    self.parse = Parse::Data;
                    match b {
                        IAC => self.data(IAC, &mut r.data),
                        WILL | WONT | DO | DONT => self.parse = Parse::Verb(b),
                        SB => {
                            self.sub.clear();
                            self.parse = Parse::Sub;
                        }
                        // NOP, GA, DM, AYT and the rest: nothing for the
                        // screen.
                        _ => {}
                    }
                }
                Parse::Verb(verb) => {
                    self.parse = Parse::Data;
                    self.negotiate(verb, b, &mut r.reply);
                }
                Parse::Sub => {
                    if b == IAC {
                        self.parse = Parse::SubIac;
                    } else if self.sub.len() < MAX_SB {
                        self.sub.push(b);
                    }
                }
                Parse::SubIac => match b {
                    SE => {
                        self.parse = Parse::Data;
                        self.subnegotiation(&mut r.reply);
                    }
                    IAC => {
                        self.parse = Parse::Sub;
                        if self.sub.len() < MAX_SB {
                            self.sub.push(IAC);
                        }
                    }
                    // Anything else ends it badly: drop it.
                    _ => {
                        self.parse = Parse::Data;
                        self.sub.clear();
                    }
                },
            }
        }
        r
    }

    /// A data byte for the screen. Without BINARY, a CR comes as `CR NUL`
    /// or `CR LF`: the NUL is padding.
    fn data(&mut self, b: u8, out: &mut Vec<u8>) {
        let binary = self.him[usize::from(BINARY)] == Q::Yes;
        if !binary && self.after_cr && b == NUL {
            self.after_cr = false;
            return;
        }
        self.after_cr = b == CR;
        out.push(b);
    }

    fn negotiate(&mut self, verb: u8, opt: u8, reply: &mut Vec<u8>) {
        let i = usize::from(opt);
        match verb {
            WILL => match self.him[i] {
                Q::No if matches!(opt, ECHO | SGA | BINARY) => {
                    self.him[i] = Q::Yes;
                    reply.extend([IAC, DO, opt]);
                }
                Q::No => reply.extend([IAC, DONT, opt]),
                Q::WantYes => self.him[i] = Q::Yes,
                Q::Yes => {}
            },
            WONT => match self.him[i] {
                Q::Yes => {
                    self.him[i] = Q::No;
                    reply.extend([IAC, DONT, opt]);
                }
                Q::WantYes => self.him[i] = Q::No,
                Q::No => {}
            },
            DO => match self.us[i] {
                Q::No if matches!(opt, NAWS | TTYPE | SGA | BINARY) => {
                    self.us[i] = Q::Yes;
                    reply.extend([IAC, WILL, opt]);
                    if opt == NAWS {
                        self.naws(reply);
                    }
                }
                Q::No => reply.extend([IAC, WONT, opt]),
                Q::WantYes => {
                    self.us[i] = Q::Yes;
                    if opt == NAWS {
                        self.naws(reply);
                    }
                }
                Q::Yes => {}
            },
            DONT => match self.us[i] {
                Q::Yes => {
                    self.us[i] = Q::No;
                    reply.extend([IAC, WONT, opt]);
                }
                Q::WantYes => self.us[i] = Q::No,
                Q::No => {}
            },
            _ => unreachable!("only the four verbs get here"),
        }
    }

    fn subnegotiation(&mut self, reply: &mut Vec<u8>) {
        // The terminal's type, when asked (`SB TTYPE SEND`): always the
        // same one, which RFC 1091 reads as the end of the list.
        if self.sub.as_slice() == [TTYPE, SEND] && self.us[usize::from(TTYPE)] == Q::Yes {
            reply.extend([IAC, SB, TTYPE, IS]);
            push_escaped(reply, self.term.as_bytes());
            reply.extend([IAC, SE]);
        }
        self.sub.clear();
    }

    /// `SB NAWS`: the window's size, its bytes escaped (a width of 255 is
    /// an IAC).
    fn naws(&self, out: &mut Vec<u8>) {
        let (cols, rows) = self.size;
        out.extend([IAC, SB, NAWS]);
        push_escaped(out, &cols.to_be_bytes());
        push_escaped(out, &rows.to_be_bytes());
        out.extend([IAC, SE]);
    }

    /// The window changed: what to tell the server, if it asked to know.
    pub fn resize(&mut self, cols: u16, rows: u16) -> Vec<u8> {
        self.size = (cols, rows);
        let mut out = Vec::new();
        if self.us[usize::from(NAWS)] == Q::Yes {
            self.naws(&mut out);
        }
        out
    }

    /// Typed bytes (or the terminal's answers) as they go on the wire: an
    /// IAC doubled and, without BINARY, Enter's lone CR as `CR LF`, the
    /// end of a line in Telnet (RFC 1123, 3.3.1).
    pub fn send(&self, bytes: &[u8]) -> Vec<u8> {
        let binary = self.us[usize::from(BINARY)] == Q::Yes;
        let mut out = Vec::with_capacity(bytes.len() + 8);
        for (i, &b) in bytes.iter().enumerate() {
            match b {
                IAC => out.extend([IAC, IAC]),
                CR if !binary => {
                    out.push(CR);
                    if bytes.get(i + 1) != Some(&LF) {
                        out.push(LF);
                    }
                }
                _ => out.push(b),
            }
        }
        out
    }
}

fn push_escaped(out: &mut Vec<u8>, bytes: &[u8]) {
    for &b in bytes {
        if b == IAC {
            out.push(IAC);
        }
        out.push(b);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn started() -> Telnet {
        let mut t = Telnet::new("xterm-256color", 80, 24);
        t.start();
        t
    }

    #[test]
    fn it_asks_for_what_a_terminal_needs() {
        let mut t = Telnet::new("xterm-256color", 80, 24);
        assert_eq!(
            t.start(),
            [
                IAC, WILL, NAWS, IAC, WILL, TTYPE, IAC, WILL, SGA, IAC, DO, SGA, IAC, DO, ECHO
            ]
        );
    }

    /// The server agrees to what we asked: no answer to its answers, and
    /// the window's size as soon as it wants it.
    #[test]
    fn agreeing_to_what_we_asked_ends_there() {
        let mut t = started();
        let r = t.receive(&[IAC, WILL, ECHO, IAC, WILL, SGA, IAC, DO, SGA, IAC, DO, NAWS]);
        assert_eq!(r.data, b"");
        assert_eq!(r.reply, [IAC, SB, NAWS, 0, 80, 0, 24, IAC, SE]);
        assert!(t.server_echoes());
        // Said again, it changes nothing.
        let r = t.receive(&[IAC, WILL, ECHO, IAC, DO, NAWS]);
        assert!(r.reply.is_empty());
    }

    /// A server that starts: we agree to what we know, refuse the rest.
    #[test]
    fn the_server_s_offers_are_answered_once() {
        let mut t = Telnet::new("vt100", 80, 24);
        let r = t.receive(&[
            IAC, DO, TTYPE, IAC, DO, 39, IAC, WILL, ECHO, IAC, WILL, 5, IAC, DO, NAWS,
        ]);
        assert_eq!(
            r.reply,
            [
                IAC, WILL, TTYPE, IAC, WONT, 39, IAC, DO, ECHO, IAC, DONT, 5, IAC, WILL, NAWS, IAC,
                SB, NAWS, 0, 80, 0, 24, IAC, SE
            ]
        );
        // Refused, they stay refused without more words.
        let r = t.receive(&[IAC, WONT, 5, IAC, DONT, 39]);
        assert!(r.reply.is_empty());
    }

    #[test]
    fn the_terminal_type_is_told_when_asked() {
        let mut t = started();
        t.receive(&[IAC, DO, TTYPE]);
        let r = t.receive(&[IAC, SB, TTYPE, SEND, IAC, SE]);
        let mut want = vec![IAC, SB, TTYPE, IS];
        want.extend(b"xterm-256color");
        want.extend([IAC, SE]);
        assert_eq!(r.reply, want);
    }

    /// Commands split across reads are still read as commands.
    #[test]
    fn commands_cut_in_two_reads() {
        let mut t = started();
        t.receive(&[IAC, DO, TTYPE]);
        let mut reply = Vec::new();
        let mut data = Vec::new();
        for b in [b'a', IAC, SB, TTYPE, SEND, IAC, SE, b'b', IAC, IAC] {
            let r = t.receive(&[b]);
            reply.extend(r.reply);
            data.extend(r.data);
        }
        assert_eq!(data, [b'a', b'b', IAC]);
        assert!(reply.starts_with(&[IAC, SB, TTYPE, IS]));
    }

    #[test]
    fn data_comes_without_commands_or_padding() {
        let mut t = started();
        let r = t.receive(b"login: \r\0ok\r\n\xff\xff\xc3\xb1");
        assert_eq!(r.data, b"login: \rok\r\n\xff\xc3\xb1");
        // NOP, GA and a subnegotiation we do not read leave nothing.
        let r = t.receive(&[b'x', IAC, 241, IAC, 249, IAC, SB, 39, 1, 2, IAC, SE, b'y']);
        assert_eq!(r.data, b"xy");
        assert!(r.reply.is_empty());
    }

    #[test]
    fn typing_escapes_iac_and_ends_lines_with_cr_lf() {
        let t = started();
        assert_eq!(t.send(b"ls\r"), b"ls\r\n");
        assert_eq!(t.send(b"a\r\nb"), b"a\r\nb");
        assert_eq!(t.send(&[b'x', IAC]), [b'x', IAC, IAC]);
        assert_eq!(t.send("ñ".as_bytes()), "ñ".as_bytes());
    }

    /// In binary, a CR is a CR and a NUL after one is data.
    #[test]
    fn binary_leaves_cr_alone() {
        let mut t = started();
        t.receive(&[IAC, DO, BINARY, IAC, WILL, BINARY]);
        assert_eq!(t.send(b"\r"), b"\r");
        assert_eq!(t.receive(b"\r\0").data, b"\r\0");
    }

    #[test]
    fn the_size_goes_again_when_it_changes() {
        let mut t = Telnet::new("xterm", 80, 24);
        assert!(t.resize(100, 30).is_empty(), "not asked for yet");
        let r = t.receive(&[IAC, DO, NAWS]);
        assert_eq!(
            r.reply,
            [IAC, WILL, NAWS, IAC, SB, NAWS, 0, 100, 0, 30, IAC, SE]
        );
        assert_eq!(
            t.resize(255, 300),
            [IAC, SB, NAWS, 0, IAC, IAC, 1, 44, IAC, SE],
            "255 is an IAC"
        );
        t.receive(&[IAC, DONT, NAWS]);
        assert!(t.resize(80, 24).is_empty());
    }

    #[test]
    fn an_endless_subnegotiation_is_dropped() {
        let mut t = started();
        let mut flood = vec![IAC, SB, TTYPE];
        flood.extend(std::iter::repeat_n(b'x', MAX_SB * 4));
        flood.extend([IAC, SE, b'k']);
        let r = t.receive(&flood);
        assert_eq!(r.data, b"k");
        assert!(r.reply.is_empty());
    }
}
