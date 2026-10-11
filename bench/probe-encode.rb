# frozen_string_literal: true

# Times pdfium rendering vs PNG encoding per page and prints the process high-water mark around one encode.
#
#   docker run --rm --platform linux/amd64 --cpuset-cpus=0 -v "$PWD":/bench:ro -w /app docuseal/docuseal:3.3.1 \
#     bundle exec ruby /bench/probe-encode.rb

require 'active_support/all'
require 'ffi'
require 'vips'
load '/app/lib/pdfium.rb'
hwm = -> { File.read('/proc/self/status')[/VmHWM:\s+(\d+)/, 1].to_i / 1024 }
rss = -> { File.read('/proc/self/status')[/VmRSS:\s+(\d+)/, 1].to_i / 1024 }
doc = Pdfium::Document.open_bytes(File.binread('/bench/test-22-pages.pdf'))
Vips.cache_set_max(0)
r = []; e = []
16.times do |i|
  page = doc.get_page(i)
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  bytes, w, h = page.render_to_bitmap(width: 1400)
  page.close
  image = Vips::Image.new_from_memory_copy(bytes, w, h, 4, :uchar)
  bytes.clear
  t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  before_rss = rss.call
  GC.start
  img = image.copy(interpretation: :srgb)
  bitdepth = 2**img.stats.to_a[1..3].pluck(2).uniq.size
  data = img.write_to_buffer('.png', compression: 6, filter: 0, bitdepth:, palette: true, Q: 95, dither: 0)
  t3 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  r << (t2 - t) ; e << (t3 - t2)
  puts "page #{i}: render #{((t2 - t) * 1000).round} ms, encode #{((t3 - t2) * 1000).round} ms, png #{data.bytesize / 1024} KB, rss #{before_rss} hwm #{hwm.call}" if i < 3
  image = img = nil
  GC.start
end
puts "render total #{(r.sum * 1000).round} ms, encode total #{(e.sum * 1000).round} ms, hwm #{hwm.call} MB"
