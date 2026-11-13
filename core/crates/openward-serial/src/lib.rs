//! Serial ports on desktop (serialport): which ones this computer has, and
//! one opened as a terminal's line, with a reader and a writer that can
//! live on threads of their own.
//!
//! Ports open for this program only: a second program (or a second tab)
//! that tries finds it in use.
//!
//! Phones have none here: iOS has no serial ports, and Android's over USB
//! are a later phase. There [`ports`] is empty and [`open`] finds nothing.

use std::io;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use std::io::{Read, Write};
use std::time::Duration;

use openward_proto::SerialLine;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use openward_proto::{FlowControl, Parity};
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use serialport::{DataBits, ErrorKind, SerialPort, SerialPortType, StopBits};

/// How long a read waits before saying nothing came: how soon a reader
/// notices it should stop.
pub const READ_WAIT: Duration = Duration::from_millis(100);

/// How long a write may wait for the other end (flow control) before it
/// gives up.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
const WRITE_WAIT: Duration = Duration::from_secs(5);

/// A port of this computer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PortInfo {
    /// What to open: `/dev/cu.usbserial-1410`, `/dev/ttyUSB0`, `COM3`.
    pub path: String,
    /// What it is, when it says: "FT232R USB UART (FTDI)". Empty otherwise.
    pub description: String,
    /// On USB: a cable or an adapter, likely what is looked for.
    pub usb: bool,
}

/// The ports there are now, USB ones first. On macOS only the `cu.` side
/// of each: its `tty.` twin waits for a carrier that consoles never give.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn ports() -> Vec<PortInfo> {
    let mut found: Vec<PortInfo> = serialport::available_ports()
        .unwrap_or_default()
        .into_iter()
        .filter(|p| !(cfg!(target_os = "macos") && p.port_name.starts_with("/dev/tty.")))
        .map(|p| {
            let (description, usb) = match &p.port_type {
                SerialPortType::UsbPort(u) => {
                    let said = match (&u.product, &u.manufacturer) {
                        (Some(p), Some(m)) if !p.contains(m.as_str()) => format!("{p} ({m})"),
                        (Some(p), _) => p.clone(),
                        (None, Some(m)) => m.clone(),
                        (None, None) => format!("USB {:04x}:{:04x}", u.vid, u.pid),
                    };
                    (said, true)
                }
                SerialPortType::BluetoothPort => ("Bluetooth".to_owned(), false),
                SerialPortType::PciPort | SerialPortType::Unknown => (String::new(), false),
            };
            PortInfo {
                path: p.port_name,
                description,
                usb,
            }
        })
        .collect();
    found.sort_by(|a, b| b.usb.cmp(&a.usb).then_with(|| a.path.cmp(&b.path)));
    found.dedup_by(|a, b| a.path == b.path);
    found
}

/// Why a port did not open.
#[derive(Debug, thiserror::Error)]
pub enum OpenError {
    #[error("there is no serial port {0}")]
    Missing(String),
    #[error("{0} is in use by another program")]
    Busy(String),
    /// On Linux, the user is not in the port's group (`dialout`).
    #[error("not allowed to open {0}")]
    Denied(String),
    #[error("{0} cannot use these settings: {1}")]
    Settings(String, String),
    #[error("{0}: {1}")]
    Other(String, String),
}

/// Opens `path` with `line`'s settings: what reads from it and what
/// writes to it.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn open(path: &str, line: &SerialLine) -> Result<(Reader, Writer), OpenError> {
    let data_bits = match line.data_bits {
        5 => DataBits::Five,
        6 => DataBits::Six,
        7 => DataBits::Seven,
        8 => DataBits::Eight,
        n => return Err(OpenError::Settings(path.into(), format!("{n} data bits"))),
    };
    let stop_bits = match line.stop_bits {
        1 => StopBits::One,
        2 => StopBits::Two,
        n => return Err(OpenError::Settings(path.into(), format!("{n} stop bits"))),
    };
    if line.baud == 0 {
        return Err(OpenError::Settings(path.into(), "0 baud".into()));
    }
    let port = serialport::new(path, line.baud)
        .data_bits(data_bits)
        .stop_bits(stop_bits)
        .parity(match line.parity {
            Parity::None => serialport::Parity::None,
            Parity::Odd => serialport::Parity::Odd,
            Parity::Even => serialport::Parity::Even,
        })
        .flow_control(match line.flow {
            FlowControl::None => serialport::FlowControl::None,
            FlowControl::Software => serialport::FlowControl::Software,
            FlowControl::Hardware => serialport::FlowControl::Hardware,
        })
        .timeout(READ_WAIT)
        .open()
        .map_err(|e| open_error(path, e))?;
    split(port, path)
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn split(port: Box<dyn SerialPort>, path: &str) -> Result<(Reader, Writer), OpenError> {
    let mut writer = port
        .try_clone()
        .map_err(|e| OpenError::Other(path.into(), e.to_string()))?;
    let _ = writer.set_timeout(WRITE_WAIT);
    Ok((Reader(port), Writer(writer)))
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn open_error(path: &str, e: serialport::Error) -> OpenError {
    let path = path.to_owned();
    match e.kind() {
        ErrorKind::Io(io::ErrorKind::NotFound) => OpenError::Missing(path),
        ErrorKind::Io(io::ErrorKind::PermissionDenied) => OpenError::Denied(path),
        // Unix: in use (TIOCEXCL, flock). Windows says the same for a port
        // that is not there: the list tells them apart.
        ErrorKind::NoDevice if ports().iter().any(|p| p.path == path) || cfg!(unix) => {
            OpenError::Busy(path)
        }
        ErrorKind::NoDevice => OpenError::Missing(path),
        ErrorKind::InvalidInput => OpenError::Settings(path, e.to_string()),
        _ => OpenError::Other(path, e.to_string()),
    }
}

/// The reading side of an open port.
pub struct Reader(Port);

#[cfg(not(any(target_os = "android", target_os = "ios")))]
impl Reader {
    /// What came, `None` if nothing did within [`READ_WAIT`]. An error,
    /// or `Some(0)`, is a port that went (the cable was pulled).
    pub fn read(&mut self, buf: &mut [u8]) -> io::Result<Option<usize>> {
        match self.0.read(buf) {
            Ok(n) => Ok(Some(n)),
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::TimedOut | io::ErrorKind::WouldBlock
                ) =>
            {
                Ok(None)
            }
            Err(e) if e.kind() == io::ErrorKind::Interrupted => Ok(None),
            Err(e) => Err(e),
        }
    }
}

/// The writing side of an open port.
pub struct Writer(Port);

#[cfg(not(any(target_os = "android", target_os = "ios")))]
impl Writer {
    /// Hands `bytes` to the system, which sends them at the port's speed.
    /// No `flush`: it would wait until they are all out, a keystroke at a
    /// time.
    pub fn write(&mut self, bytes: &[u8]) -> io::Result<()> {
        self.0.write_all(bytes)
    }

    /// A break: the line held low for a while, which some consoles (a
    /// router's ROM monitor) take as a signal.
    pub fn send_break(&mut self) -> io::Result<()> {
        self.0.set_break().map_err(io::Error::other)?;
        std::thread::sleep(Duration::from_millis(300));
        self.0.clear_break().map_err(io::Error::other)
    }
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
type Port = Box<dyn SerialPort>;

/// No port on a phone: nothing of this kind is ever made. Boxed, so the
/// reader and the writer are dropped as on the desktop.
#[cfg(any(target_os = "android", target_os = "ios"))]
type Port = Box<std::convert::Infallible>;

#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn ports() -> Vec<PortInfo> {
    Vec::new()
}

#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn open(path: &str, _: &SerialLine) -> Result<(Reader, Writer), OpenError> {
    Err(OpenError::Missing(path.to_owned()))
}

#[cfg(any(target_os = "android", target_os = "ios"))]
impl Reader {
    pub fn read(&mut self, _: &mut [u8]) -> io::Result<Option<usize>> {
        match *self.0 {}
    }
}

#[cfg(any(target_os = "android", target_os = "ios"))]
impl Writer {
    pub fn write(&mut self, _: &[u8]) -> io::Result<()> {
        match *self.0 {}
    }
    pub fn send_break(&mut self) -> io::Result<()> {
        match *self.0 {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_list_has_each_port_once() {
        let ports = ports();
        let mut paths: Vec<_> = ports.iter().map(|p| p.path.as_str()).collect();
        paths.dedup();
        assert_eq!(paths.len(), ports.len());
        if cfg!(target_os = "macos") {
            assert!(
                paths.iter().all(|p| !p.starts_with("/dev/tty.")),
                "{paths:?}"
            );
        }
    }

    #[test]
    fn bad_settings_and_missing_ports_say_so() {
        let bad = SerialLine {
            data_bits: 9,
            ..SerialLine::default()
        };
        assert!(matches!(
            open("/dev/null", &bad),
            Err(OpenError::Settings(_, _))
        ));
        let missing = if cfg!(windows) {
            "COM250"
        } else {
            "/dev/openward-no-such-port"
        };
        assert!(matches!(
            open(missing, &SerialLine::default()),
            Err(OpenError::Missing(_))
        ));
    }

    /// A pseudo-terminal stands in for a cable: what one end writes the
    /// other reads, and (on Linux) a second open finds the port taken.
    /// macOS cannot set a pseudo-terminal's speed: there the test takes
    /// the pair's end as it is.
    #[cfg(unix)]
    #[test]
    fn a_line_carries_both_ways_and_is_ours_alone() {
        let (mut cable, other_end) = serialport::TTYPort::pair().unwrap();
        let path = other_end.name().unwrap();
        let (mut reader, mut writer) = if cfg!(target_os = "macos") {
            split(Box::new(other_end), &path).unwrap()
        } else {
            let line = open(&path, &SerialLine::default()).unwrap();
            assert!(matches!(
                open(&path, &SerialLine::default()),
                Err(OpenError::Busy(_))
            ));
            line
        };

        cable.write_all(b"Router>").unwrap();
        let mut got: Vec<u8> = Vec::new();
        let mut buf = [0u8; 64];
        for _ in 0..50 {
            if let Some(n) = reader.read(&mut buf).unwrap() {
                got.extend(&buf[..n]);
            }
            if got.len() >= 7 {
                break;
            }
        }
        assert_eq!(got, b"Router>");

        writer.write(b"enable\r").unwrap();
        let mut said = [0u8; 7];
        cable.read_exact(&mut said).unwrap();
        assert_eq!(&said, b"enable\r");
    }
}
