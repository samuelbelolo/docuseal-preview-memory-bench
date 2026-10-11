# PDF preview memory bench

Measures the memory of `Templates::ProcessDocument.generate_document_preview_images` on the public
`docuseal/docuseal` image, with any version of `lib/templates/process_document.rb` bind-mounted over the
one in the image, so every variant runs on the same image.

## What a run does

1. Copies a golden data volume (SQLite database, one account, created once by `setup-golden.sh`) into a
   fresh volume.
2. Starts the image with `--memory=740m --memory-swap=740m --cpuset-cpus=<cpuset>` (no swap) and the
   variant mounted read-only over `/app/lib/templates/process_document.rb`.
3. Starts a sidecar that finds the container cgroup (`docker/<id>` or `system.slice/docker-<id>.scope`) and reads the container's cgroup v2 files from outside the container every 0.25 s
   (`memory.current`, `memory.peak`, `anon` and `file` from `memory.stat`, `oom_kill` from `memory.events`).
4. Waits 20 s, then uploads `test-22-pages.pdf` through the web upload form (`POST /templates_upload`, the
   request the "Upload" button sends) 5 times one after another, 5 s apart, then 2 times at once.
   In the open-source edition this request renders the previews inline in the Puma thread, so the request
   duration is the preview duration.
5. Stops the container, copies `/data/docuseal` out, and lists every `preview_images` blob
   (filename and `active_storage_blobs.checksum`, the base64 MD5 of the PNG), checking each one against
   the MD5 of the file on disk. The copy is then deleted: it holds the generated `SECRET_KEY_BASE` and
   signing key of the throwaway account.

If the app process is OOM-killed, the container exits (`OOMKilled: true`) and the run stops there.

## Requirements

Docker with cgroup v2 (Docker Desktop or a recent Linux), `bash`, `curl`, `perl`, `sqlite3`, `openssl`,
and `ruby` 2.6 or newer on the host (for `make-test-pdf.rb` and `summarize.rb`, standard library only).
On Apple silicon, `linux/amd64` runs under Rosetta; set `PLATFORM=linux/arm64` for a native run.

## Usage

```bash
ruby make-test-pdf.rb test-22-pages.pdf      # deterministic 22-page A4 text PDF (already committed)
bash setup-golden.sh                         # once: golden volume + session cookie in .state/

bash run.sh variants/stock.rb A-stock-1cpu-r1 0
bash run.sh variants/sequential.rb B-sequential-1cpu-r1 0
bash run.sh variants/stock.rb A-stock-2cpu-r1 0,1
MEMORY=2g bash run.sh variants/stock.rb A-stock-2g-1cpu-r1 0
```

Arguments: `run.sh <variant.rb> <label> [cpuset] [pdf]`. Environment: `MEMORY` (default `740m`),
`SETTLE` (seconds before the first upload, default 20), `IMAGE` (default `docuseal/docuseal:3.3.1`),
`PLATFORM` (default `linux/amd64`), `PORT` (default 3999), `SAMPLER_CPUSET` (CPU of the sidecar, default
the last CPU of the Docker host).

Each run writes `results/<label>/`: `uploads.tsv` (start, end, HTTP status per upload), `samples.jsonl`,
`container.json` (`OOMKilled`, exit code), `previews.tsv`, `app.log` and `summary.json`. `summarize.rb` prints one line per run; `preview_signatures` is an MD5 over the 16
`filename:checksum` pairs of a document, so identical previews give the same signature in every run and
every variant.

`ruby table.rb` prints a Markdown table of every run in `results/`. `probe-encode.rb` (run inside the image,
command in its header) times rendering vs PNG encoding per page and prints the memory high-water mark of
one encode.

`.state/cookies.txt` holds the session of the throwaway local bench account; delete `.state/` and the
`ds-bench-golden` volume when done:

```bash
docker volume rm ds-bench-golden; rm -rf .state
```

## Variants

- `variants/stock.rb`: `lib/templates/process_document.rb` from `master` (identical to the 3.3.1 image).
- `variants/sequential.rb`: the proposed change (one page at a time).
- `variants/bounded.rb`: keeps the pool of 2, renders pages in slices of 2 and waits for each slice.
- `variants/diag/`: diagnostic variants used to explain the numbers, not proposals.
