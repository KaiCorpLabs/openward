.PHONY: test lint fmt deny bench corpus clean

TERMBENCH := spikes/s1-terminal/termbench
CORPUS := spikes/s1-terminal/corpus/synthetic

test:
	cd core && cargo test --workspace

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

clean:
	rm -rf core/target $(TERMBENCH)/target $(CORPUS)
