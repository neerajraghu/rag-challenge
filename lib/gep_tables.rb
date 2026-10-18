require "set"

# Rebuilds the tables of the Global Economic Prospects report from word positions.
# The PDF text has one line per cell. Rows are the cells that share a vertical position,
# and each number is matched to the column heading above it, so a value never loses its column.
module GepTables
  TITLE = /\ATABLE [A-Z]?\d+(?:\.\d+)*\b/
  CELL_MAX_HEIGHT = 8.0
  ROW_TOLERANCE = 2.5
  YEAR = %r{\A(?:19|20)\d\d(?:/\d{2,4})?[ef]?\z|\A(?:19|20)\d\d[–-]\d{2,4}\z}
  NUMBER = /\A[-–−]?\d[\d,]*(?:\.\d+)?%?\z|\A\.\.\z|\An\.a\.\z|\A…\z/
  LABEL_GAP = 12 # a cell this close to the first column, or further right, is a value

  Cell = Struct.new(:text, :x, :xmax, :y, :height, :node, keyword_init: true)

  def self.cells(page)
    page.css("line").map do |l|
      Cell.new(text: l.css("word").map(&:text).join(" ").unicode_normalize(:nfkc), x: l["xmin"].to_f,
               xmax: l["xmax"].to_f, y: l["ymin"].to_f, height: l["ymax"].to_f - l["ymin"].to_f, node: l)
    end
  end

  # [{title:, cells: [...]}], one per table title found on the page.
  def self.regions(page)
    all = cells(page)
    titles = all.select { |c| c.text.match?(TITLE) && c.height >= 9 }.sort_by(&:y)
    titles.each_with_index.map do |title, i|
      stop = [titles[i + 1]&.y, caption_after(all, title)].compact.min || Float::INFINITY
      body = all.select { |c| c.y >= title.y && c.y < stop && (c.equal?(title) || c.height < CELL_MAX_HEIGHT) }
      { title: title, cells: body }
    end
  end

  # A figure or box caption below the table ends it.
  def self.caption_after(all, title)
    all.select { |c| c.y > title.y && c.height >= 9 && c.text.match?(/\A(FIGURE|BOX|FIGURES)\b/) }.map(&:y).min
  end

  # Lines that belong to a table and must not appear again as plain text.
  def self.table_nodes(page)
    regions(page).flat_map { |r| r[:cells].map(&:node) }.to_set
  end

  # Returns an array of short self-contained paragraphs, one per table row.
  def self.paragraphs(page)
    regions(page).flat_map { |r| table_paragraphs(r) }
  end

  def self.table_paragraphs(region)
    title = region[:title]
    cells = region[:cells].reject { |c| c.equal?(title) }
    rows = group_rows(cells)
    header_at = rows.index { |r| header?(r) }
    name = title.text
    return [name] + rows.map { |r| "#{name}: #{r.sort_by(&:x).map(&:text).join(' ')}" } unless header_at
    supers = rows[0...header_at].reject { |r| r.first.text.start_with?("(") }.flatten
    notes = rows[0...header_at].select { |r| r.first.text.start_with?("(") }.map { |r| r.map(&:text).join(" ") }
    [([name] + notes).join(" ")] + body_rows(name, rows.drop(header_at), supers)
  end

  def self.header?(row)
    row.count { |c| c.text.match?(YEAR) } >= 3
  end

  # A new header row (for example fiscal years) applies to the rows under it. A row with no numbers,
  # such as "Fiscal-year basis" or "Memo items", names the group of the rows under it.
  def self.body_rows(name, rows, supers)
    columns = nil
    group = nil
    rows.filter_map do |r|
      if header?(r)
        columns = columns_for(r, supers)
        label = r.reject { |c| c.text.match?(YEAR) }.sort_by(&:x).map(&:text).join(" ").strip
        group = label unless label.empty?
        next
      end
      text, label_only = row_text(name, group, r, columns)
      group = label_only if label_only
      text
    end
  end

  def self.group_rows(cells)
    cells.sort_by { |c| [c.y, c.x] }.each_with_object([]) do |c, rows|
      if rows.any? && (c.y - rows.last.first.y).abs <= ROW_TOLERANCE
        rows.last << c
      else
        rows << [c]
      end
    end
  end

  # Each year heading with the wider heading above it, such as "Percentage-point differences from January".
  def self.columns_for(header_row, supers)
    years = header_row.select { |c| c.text.match?(YEAR) }.sort_by(&:x)
    years.map do |y|
      over = supers.select { |s| s.x < y.xmax && y.x < s.xmax }.sort_by(&:y).map(&:text)
      { label: y.text, x: y.x, xmax: y.xmax, group: over.join(" ") }
    end
  end

  # Returns [text, label_only]. label_only is set when the row has no numbers, so it can name a group.
  def self.row_text(name, group, row, columns)
    left = columns.map { |c| c[:x] }.min - LABEL_GAP
    values, label = row.partition { |c| c.text.match?(NUMBER) && c.x >= left }
    label_text = label.sort_by(&:x).map(&:text).join(" ").strip
    return nil if label_text.empty? && values.empty?
    return ["#{name}: #{label_text}", label_text] if values.empty?
    pairs = values.sort_by(&:x).map do |v|
      col = columns.min_by { |c| (c[:xmax] - v.xmax).abs }
      "#{[col[:group], col[:label]].reject(&:empty?).join(' ')} = #{v.text}"
    end
    ["#{name}, #{[group, label_text].compact.join(', ')}: #{pairs.join('; ')}", nil]
  end
end
