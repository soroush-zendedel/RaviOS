# Ollama app seed

Place offline artifacts here (no automated prepare-image script yet):

- `image.tar` — Docker image archive for `ravi-ollama:cpu`
  (formerly `artifacts/ollama-bundle/image/ravi-ollama-image.tar`)
- `models/qwen2.5-0.5b.tar` — model blob archive
  (formerly `artifacts/ollama-bundle/models/qwen2.5-0.5b.tar`)

`app.json` controls load order, networks, volumes and autostart.
