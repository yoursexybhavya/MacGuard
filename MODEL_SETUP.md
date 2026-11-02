# Local AI Model Setup & Management Guide: Project MACGUARD

---

## 1. Selected Model Overview

* **Model Name**: Qwen 2.5 3B Instruct
* **Quantization**: `Q4_K_M` (4-bit medium K-quant)
* **License**: Apache 2.0 (Permissive for commercial and private use)
* **Model Size**: ~1.9 GB on disk
* **Active RAM Footprint**: ~2.5 GB Unified Memory
* **Context Window**: 32,768 tokens (set to 512–2048 for maintenance operations)
* **Inference Speed**: ~110 tokens/sec on Apple M5 Pro Metal GPU
* **Provider**: [Alibaba Cloud / Qwen Team](https://github.com/QwenLM/Qwen2.5) via Ollama

---

## 2. Why Qwen 2.5 3B?

1. **Superior Tool Calling**: Qwen 2.5 was specifically trained for structured JSON output and function calling, achieving near-perfect schema compliance without formatting errors.
2. **Thermal & Battery Balance**: While larger 7B or 14B models consume 6–10 GB of memory and induce thermal throttling during continuous scans, the 3B parameter model runs silently with negligible battery drain.
3. **Low Latency**: Under 200ms cold start and over 100 tok/sec streaming on Apple Silicon unified memory.

---

## 3. Installation & Verification

### Step 1: Ensure Ollama is Installed & Running
Download and install [Ollama for macOS](https://ollama.ai/download), or install via Homebrew:
```bash
brew install ollama
```
Launch Ollama (or verify it is active):
```bash
ollama serve
```

### Step 2: Download the Specialized Model
Pull the official quantized model:
```bash
ollama pull qwen2.5:3b
```

### Step 3: Verify Integrity & Benchmark
Test local inference with a structured JSON prompt:
```bash
curl -s http://127.0.0.1:11434/api/generate -d '{
  "model": "qwen2.5:3b",
  "prompt": "Respond with {\"status\": \"ready\", \"engine\": \"macguard\"}",
  "stream": false,
  "format": "json"
}'
```

Expected output:
```json
{
  "model": "qwen2.5:3b",
  "response": "{\n  \"status\": \"ready\",\n  \"engine\": \"macguard\"\n}",
  "done": true
}
```

---

## 4. Alternative Model Options

If your hardware configuration changes or you wish to switch models:

| Model Tag | RAM | Speed | Command | Best For |
| :--- | :--- | :--- | :--- | :--- |
| `qwen2.5:3b` | ~2.5 GB | ~110 tok/s | `ollama pull qwen2.5:3b` | **Default Recommendation** |
| `llama3.2:3b`| ~2.6 GB | ~95 tok/s | `ollama pull llama3.2:3b` | Alternative 3B generalist |
| `qwen2.5:1.5b`| ~1.2 GB | ~150 tok/s | `ollama pull qwen2.5:1.5b` | Ultra-lightweight (MacBook Air 8GB) |
| `qwen2.5:7b` | ~5.8 GB | ~55 tok/s | `ollama pull qwen2.5:7b` | Heavy reasoning workstation |

MacGuard automatically detects any installed model configured in `SettingsView`.

---

## 5. Offline Operation

After running `ollama pull qwen2.5:3b`, internet access is never required. You can disconnect Wi-Fi entirely; all file organization, scanning, and recommendations will continue functioning locally.
