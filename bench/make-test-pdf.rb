# frozen_string_literal: true

# Writes a deterministic A4 text-only PDF (default 22 pages) with no dependencies.
#
#   ruby make-test-pdf.rb test-22-pages.pdf [pages]

WORDS = %w[
  agreement party document clause period notice payment term condition property rent deposit
  schedule annex signature date amount owner tenant service delivery invoice account review
  section article obligation right duty insurance repair access keys inventory charges total
  monthly yearly start end renewal termination address contact email phone record copy original
].freeze

PAGE_WIDTH = 595
PAGE_HEIGHT = 842
LINES_PER_PAGE = 58
WORDS_PER_LINE = 13

out_path = ARGV.fetch(0) { abort 'usage: ruby make-test-pdf.rb OUT.pdf [pages]' }
pages = Integer(ARGV.fetch(1, '22'))
random = Random.new(1235)

escape = ->(text) { text.gsub(/([\\()])/, '\\\\\1') }

contents = Array.new(pages) do |page_index|
  lines = ["BT /F2 16 Tf 56 790 Td (#{escape.call("Sample document - page #{page_index + 1} of #{pages}")}) Tj ET"]

  LINES_PER_PAGE.times do |line_index|
    text = Array.new(WORDS_PER_LINE) { WORDS[random.rand(WORDS.size)] }.join(' ')
    y = 760 - (line_index * 12)

    lines << "BT /F1 10 Tf 56 #{y} Td (#{escape.call(text.capitalize)}.) Tj ET"
  end

  lines << "0.5 w 56 50 m 539 50 l S BT /F1 9 Tf 280 36 Td (#{page_index + 1}) Tj ET"
  lines.join("\n")
end

objects = []
objects << '<< /Type /Catalog /Pages 2 0 R >>'
kids = Array.new(pages) { |i| "#{5 + (i * 2)} 0 R" }.join(' ')
objects << "<< /Type /Pages /Kids [#{kids}] /Count #{pages} >>"
objects << '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'
objects << '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>'

contents.each_with_index do |stream, i|
  objects << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{PAGE_WIDTH} #{PAGE_HEIGHT}] " \
             "/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents #{6 + (i * 2)} 0 R >>"
  objects << "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream"
end

pdf = +"%PDF-1.4\n"
offsets = objects.each_with_index.map do |body, i|
  offset = pdf.bytesize
  pdf << "#{i + 1} 0 obj\n#{body}\nendobj\n"
  offset
end

xref_offset = pdf.bytesize
pdf << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
offsets.each { |offset| pdf << format("%010d 00000 n \n", offset) }
pdf << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref_offset}\n%%EOF\n"

File.binwrite(out_path, pdf)
puts "#{out_path}: #{pages} pages, #{pdf.bytesize} bytes"
