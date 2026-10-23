.PHONY: test lint fmt deny ci ci-quick ci-check bench corpus conformance conformance-record ssh ssh-down clean

TERMBENCH := spikes/s1-terminal/termbench
CORPUS := spikes/s1-terminal/corpus/synthetic

# Without the S2 servers the connection tests pass without testing anything.
test:
	@nc -z 127.0.0.1 22100 2>/dev/null || echo "warning: S2 servers not running: the SSH tests skip (make ssh, or make ci)"
	cd core && cargo test --workspace

# The CI, run here (tool/ci.sh): everything before a release or a push to
# main; without the window tests for each commit; and whether HEAD passed.
ci:
	tool/ci.sh

ci-quick:
	tool/ci.sh --quick

ci-check:
	tool/ci.sh --check

lint:
	cd core && cargo fmt --all -- --check
	cd core && cargo clippy --workspace --all-targets -- -D warnings
	cd $(TERMBENCH) && cargo fmt -- --check
	cd $(TERMBENCH) && cargo clippy --all-targets -- -D warnings

fmt:
	cd core && cargo fmt --all
	cd $(TERMBENCH) && cargo fmt

deny:
	cd core && cargo deny check

# Smoke test of the terminal benchmark (spike S1); real runs: docs/spikes/S1-terminal.md
bench:
	cd $(TERMBENCH) && cargo build --release
	$(TERMBENCH)/target/release/termbench gen $(CORPUS) --mb 2
	$(TERMBENCH)/target/release/termbench run $(CORPUS)/*.txt --scrollback 10000
	$(TERMBENCH)/target/release/termbench echo --iterations 5000
	$(TERMBENCH)/target/release/termbench mem --tabs 2 --scrollback 5000

# Spike S1 real-session corpus, recorded offline in a container (podman or docker)
corpus:
	spikes/s1-terminal/corpus/record.sh

# Spike S1.6 correctness: replay the committed tmux references (vttest,
# Unicode widths, real programs) into both engines. Needs libghostty-vt
# (core/crates/openward-ghostty/build-libghostty.sh).
CONFORMANCE := spikes/s1-terminal/corpus/conformance
REPORTS := spikes/s1-terminal/results/conformance
conformance:
	cd $(TERMBENCH) && cargo build --release --features ghostty
	mkdir -p $(REPORTS)
	for n in vttest unicode apps; do \
	  $(TERMBENCH)/target/release/termbench conform $(CONFORMANCE)/$$n.out \
	    $(CONFORMANCE)/$$n.ref.jsonl $(REPORTS)/$$n.md --engine all || exit 1; \
	done
	$(TERMBENCH)/target/release/termbench reports --engine all

# Re-record those references in the offline container (about 10 minutes)
conformance-record:
	spikes/s1-terminal/corpus/conformance.sh

# Spike S2: real SSH servers in containers and the russh interop matrix
ssh:
	spikes/s2-ssh/servers/up.sh
	cd spikes/s2-ssh/sshprobe && cargo run --release -- matrix

ssh-down:
	spikes/s2-ssh/servers/down.sh

clean:
	rm -rf core/target $(TERMBENCH)/target $(CORPUS)
