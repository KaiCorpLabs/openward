# S2 · SSH con `russh` (escritorio)

Plan, matriz y resultados: [docs/spikes/S2-ssh.md](../../docs/spikes/S2-ssh.md).

| Ruta | Contenido |
|---|---|
| `servers/` | Servidores SSH reales en contenedores, solo en `127.0.0.1`: OpenSSH 8.9, 9.2 y 10.0, Dropbear, y una cadena de saltos. `up.sh` los arranca y genera el material de prueba fuera del repositorio; `down.sh` los para |
| `sshprobe/` | Cliente sobre `russh` con la forma del futuro `openward-ssh`: transporte genérico (TCP, ProxyCommand, salto), autenticación, known hosts y túneles. El binario ejecuta la matriz (`matrix`), las medidas (`bench`) y la prueba de SFTP de la v0.2 (`sftp`: `russh-sftp` con 1 GiB de subida y bajada, cortado y reanudado; con `--rtt` pasa por un relé que añade latencia). El banco de render de S1 lo usa para su terminal SSH |
| `results/` | Matriz y medidas en JSON; SFTP en `macos-sftp.txt` |

```bash
make ssh          # arranca los servidores y pasa la matriz
make ssh-down     # los para
cd sshprobe && cargo run --release -- bench --port 22100
cd sshprobe && cargo run --release -- sftp --mib 256 --rtt 50 --only 10.0
```

El banco de render se conecta a un servidor con `S1_SHELL=ssh://demo@127.0.0.1:22100?key=<ruta a id_ed25519>`. La clave está en el material de prueba (`~/Library/Caches/openward/s2-fixtures` en macOS).
