# Qwen3.6-35B on two Intel Arc GPUs

Run a 35-billion-parameter language model — Qwen3.6-35B-A3B — split across
two Intel Arc graphics cards, using one downloaded file and one command.
You get a local, private, OpenAI-compatible API endpoint with up to a
65,536-token context window.

This was built and measured for people who want to run a serious model on
about $500 of GPUs: two Intel Arc B580 cards (12 GB each). Everything here
was tested on two Arc Pro B70 cards (same GPU family, more memory) with
per-card VRAM usage measured against the B580's usable budget throughout —
**but nobody has yet confirmed it on actual B580 cards. If you have two
B580s, you are the test we could not run. Please open an issue with your
result either way.**

What you can expect, honestly stated:

| | Measured on our cards |
|---|---|
| Answers correctly | Yes — including finding one sentence buried 92,000 tokens deep in a document |
| Response speed (short chats) | ~39 tokens/second |
| Response speed (very long documents) | ~15–19 tokens/second |
| Reading speed for comparison | ~5–8 tokens/second |
| Time to read in a 60,000-token document | ~2 minutes, one time, then it answers |
| VRAM per card, worst case measured | 10.8 GB with the 65,536 context nearly full |

Speed numbers come from Arc Pro B70 cards and **will differ on B580s**.

**A note on "12 GB":** a B580 has 12 GB of VRAM on the box, but not all
of it is usable by a program — the driver and system reserve a slice,
and what software actually sees on a real B580 is about **11.3 GB**.
Every memory number in this project was engineered and measured against
that 11.3 GB ceiling, not the 12 on the spec sheet. When we say
"10.8 GB worst case," the headroom to judge it against is 11.3.

---

## What you need before starting

- A Linux PC with **two Intel Arc graphics cards installed and working**,
  with current Intel graphics drivers. We tested on Ubuntu 24.04 LTS with
  the `xe` kernel driver and the Intel open-source Mesa Vulkan driver,
  **Mesa 25.2.8** (Vulkan API 1.4.318). To check yours, run:

  ```
  vulkaninfo --summary
  ```

  You should see **two** entries named `Intel(R) Graphics`. A third entry
  called `llvmpipe` is normal — that is a software renderer that is always
  present. Ignore it. If you see fewer than two Intel entries, stop here:
  the driver setup needs fixing first, and that is outside what this
  guide covers.
- About **25 GB of free disk space** on a local drive (not a network
  drive — the model loads much faster from local disk).
- A user account that can use `sudo`.

## Step 1 — Install Docker

First, check whether you already have it:

```
docker compose version
```

If that prints a version number (for example
`Docker Compose version v2.27.0`), go to Step 2. If it prints an error,
install Docker:

```
curl -fsSL https://get.docker.com | sudo sh
```

You should see it install a list of packages and finish without errors.
Then let your user run Docker without sudo:

```
sudo usermod -aG docker $USER
```

**Log out and log back in** (or reboot). Then run
`docker compose version` again — you should now see the version number.

## Step 2 — Get this repository

```
git clone https://github.com/AscalonSolutions/qwen3.6-35b-two-b580s.git
cd qwen3.6-35b-two-b580s
```

You should see the folder appear with a `Dockerfile`, `docker-compose.yml`,
and a `models` folder inside.

## Step 3 — Create your settings file

```
cp .env.example .env
```

Now find your system's "render" group number:

```
getent group render
```

You should see something like `render:x:993:` — the number in the middle
(here `993`) is what you need — there may be a name after it, ignore the name. Open `.env` in any text editor and set
`RENDER_GID=` to your number. Leave the other lines alone for now.

## Step 4 — Download the model (19.7 GB — this is the long step)

The model is a single file published by bartowski on Hugging Face. This
download takes a while (minutes on fast fiber, hours on slow connections)
and can be resumed if interrupted — rerunning the same command continues
where it left off.

```
wget -c -O models/Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf "https://huggingface.co/bartowski/Qwen_Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf?download=true"
```

You should see a progress bar counting up to 19,699,553,920 bytes.

**Verify the file** — this checks your download is exactly the published
file, bit for bit. It reads the whole 19.7 GB, so it sits silent for a few
minutes before printing:

```
sha256sum models/Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf
```

You should see exactly this:

```
afc7238af403ed454b7846454091b5e38b07575bdbb64c3e86777414dde4193c
```

If the letters and numbers differ **at all**, the download is corrupt:
delete the file and rerun the download command.

## Step 5 — Build and start the server

The first launch compiles the inference engine from source inside the
container, pinned to the exact version we tested — nothing you run is
untested code. This takes several minutes and prints a lot of compiler
output. That is normal.

```
docker compose up -d --build
```

You should see the build run, then `Started` (or `Running`). Now watch it
load the model:

```
docker compose logs -f
```

You should see `loading model`, a pause (up to a minute or two while
19.7 GB reads from disk the first time), then:

```
llama_server: model loaded
llama_server: listening on http://0.0.0.0:8080
```

Press Ctrl-C to stop watching the log (the server keeps running).

## Step 6 — Talk to it

Send it a first question:

```
curl -s http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"TYPE-YOUR-QUESTION-HERE"}],"temperature":0,"max_tokens":300}'
```

> Change **only** the words `TYPE-YOUR-QUESTION-HERE` — keep the
> quotation marks around them. Everything else stays exactly as written.

You should see a JSON reply with the model's answer inside it.

**A note on your first request:** the very first question after each start
is slower than normal (the GPUs compile their programs on first use).
Every request after that runs at full speed.

**You don't have to talk to it with commands.** For a chat experience
like the subscription services — a browser window, conversation history,
copy buttons — connect a chat app to this server. Two popular free ones:
**[Open WebUI](https://github.com/open-webui/open-webui)** and
**[Jan](https://jan.ai)**. In either, add a custom "OpenAI-compatible"
model server and give it the address `http://localhost:8080/v1` (no API
key needed). We tested the server with these instructions, not each app —
their own setup guides cover the rest.

To stop the server: `docker compose down`. To start it again:
`docker compose up -d` (no rebuild needed after the first time).

---

## How much context can I use?

The context window is how much text the model can hold at once — your
question, the documents you paste, and its answers combined.

Set it with `CONTEXT=` in `.env`, then `docker compose up -d` again.

| Setting | Roughly | Two 12 GB cards |
|---|---|---|
| `32768` (default) | a very long chat, or ~80 pages | Tested. Comfortable margin. |
| `65536` (maximum) | ~160 pages in one go | Tested nearly full: 10.8 GB peak on the busier card, against the 11.3 GB usable ceiling. This is the maximum we recommend. |
| above 65536 | | **Do not.** VRAM use grows both with the setting *and* as the window fills; our measurements put a full window past the 11.3 GB usable ceiling above this. |

**Have bigger Intel cards?** A higher context ceiling is possible on
Intel GPUs with more VRAM — the cost is predictable: about 14 MB per
1,000 tokens of window, plus about 7 MB per 1,000 tokens actually
filled, on the busier card. On 32 GB cards we ran a 98,304-token window
and pulled a fact from 92,000 tokens deep. Raise `CONTEXT` in `.env`
accordingly — it is the only number you need to change. **This project
was specifically designed and measured for two Intel Arc B580s; cards
that size or larger are the intended hardware.** Smaller or single-card
setups are untested and outside its design.

## If it goes wrong

| What you see | What it means | What to do |
|---|---|---|
| `you must set RENDER_GID` when starting | Step 3 wasn't finished | Run `getent group render`, put the number in `.env` |
| Errors mentioning `/dev/dri` or `Permission denied` on the GPU | The container can't reach the graphics cards | Check `RENDER_GID` matches `getent group render`; reboot if drivers were just installed |
| `vulkaninfo --summary` shows fewer than two Intel entries | Driver or hardware problem | Fix the driver install first — this guide assumes working cards |
| Only one GPU fills with memory when loading | The split didn't engage | Open an issue with your `docker compose logs` output |
| Server prints `model loaded` but a request errors about the model path | `MODEL_FILE` in `.env` doesn't match the file in `models/` | Make the names identical |
| Out-of-memory error on the GPU | Context too large for your cards | Lower `CONTEXT` in `.env` |
| Long silence after sending a big document | Normal — it's reading | A 60,000-token document takes ~2 minutes before the answer starts |
| First request after startup is slow | Normal — one-time GPU program compile | The second request is full speed |
| Download hash doesn't match | Corrupt download | Delete the file, rerun the `wget` command |

## What was actually tested (and what wasn't)

- Correct answers verified at temperature 0 on a fixed prompt set — short
  factual, 500 tokens of code generation, and needle-in-a-haystack
  retrieval from 13,000-, 62,000-, and 92,000-token documents — with
  two-card output compared token-for-token against single-card output.
- Per-card VRAM measured continuously (5 samples/second) through every
  load and request: growth was smooth every time, with no spikes above the
  settled values.
- Tested on Arc Pro B70 (same Battlemage GPU family as the B580, 32 GB).
  Memory was engineered against the B580's real usable budget of
  ~11.3 GB (not the 12 GB on the spec sheet — see the note at the top),
  but the B580 differs in ways we could not emulate (less VRAM, Small-BAR
  CPU access). **A confirmation run on real B580s is the missing piece —
  please report yours.**
- Not tested: Windows, single-card setups, other Arc models, contexts
  above 98,304, sustained multi-user load.

## Credits and license

- **Model:** Qwen3.6-35B-A3B by the Qwen team — Apache 2.0.
- **Quantized file:** [bartowski](https://huggingface.co/bartowski/Qwen_Qwen3.6-35B-A3B-GGUF)
  (imatrix-calibrated IQ4_XS) — download it from his repository, verify the
  hash above. This project would be nothing without this file. He runs his
  quantization work on donated compute — if this project is useful to you,
  consider supporting him at [ko-fi.com/bartowski](https://ko-fi.com/bartowski).
- **Engine:** [llama.cpp](https://github.com/ggml-org/llama.cpp) (MIT),
  built at commit `178a6c449` — the exact version all measurements used.
- This repository: Apache 2.0. See `NOTICE` for full attributions.
