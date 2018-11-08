# encoding: UTF-8
require 'csv'
require 'logger'
require 'time'

class CsvNormalizationException < StandardError
  attr_reader :column, :message
  def initialize(column, val, err)
    @column = column
    @message = "Error normalizing column '#{column}' with value '#{val}': #{err}"
  end
end

class CsvNormalizer

  SECONDS_IN_HOUR = 3600
  SECONDS_IN_MINUTE = 60
  DURATION_RE = Regexp.new('(\d{1,2}):(\d{2}):(\d{2}\.\d+)')

  attr_accessor :logger
  def initialize(logger = Logger.new($stderr))
    self.logger = logger
    # see https://bugs.ruby-lang.org/issues/10085
    if RUBY_VERSION < '2.4'
      logger.warn "Possibly invalid upcasing of names"
    end

  end

  # Convert the provided `timestr` from US/Pacific to US/Eastern and
  # convert to iso8601. Raise an exception if the string cannot be
  # parsed by `Time.parse`
  def normalize_timestamp_string(timestr)
    # If we needed more advanced timezone manipulation, pulling in the
    # ActiveSupport::TimeZone gem would probably make sense.  However,
    # for this tiny bit of functionality, we can do it all with the
    # ruby standard library
    original_tz = ENV['TZ']
    begin
      ENV['TZ'] = ':America/Los_Angeles'
      ts = Time.strptime(timestr, '%m/%d/%y %H:%M:%S %P')
      ENV['TZ'] = ':America/New_York'
      return ts.utc.getlocal.iso8601
    ensure
      ENV['TZ'] = original_tz
    end
  end

  # Convert the provided `zipstr` to an int and return a zero padded
  # string. Raise an exception if the string cannot be converted to an
  # int.
  def normalize_zip_string(zipstr)
    # use Integer to raise an exception on error
    '%05d' % Integer(zipstr)
  end

  # Convert the provided `namestr` to upper case. Note that different
  # languages use different conversion rules so this is not guaranteed
  # to work for names from all languages (e.g. Turkish)
  def normalize_fullname_string(namestr)
    namestr&.upcase
  end

  # Convert the provided `durationstr` in the format HH:MM:SS.MS into
  # a float representing the fractional seconds. Raise an exception if
  # the string cannot be parsed
  def normalize_duration_string(durationstr)
    if m = DURATION_RE.match(durationstr)
      Integer(m[1]) * SECONDS_IN_HOUR +
        Integer(m[2]) * SECONDS_IN_MINUTE +
        Float(m[3])
    else
      raise "Cannot parse duration"
    end
  end

  # Normalize `columnkey` in `row` using `method`.  If this fails,
  # raise a CsvNormalizationException
  def normalize_column(row, columnkey, method)
    if !row.has_key?(columnkey)
      raise CsvNormalizationException.new(columnkey,
                                          nil,
                                          "column is missing from row")
    end
    begin
      row[columnkey] = self.send(method, row[columnkey])
    rescue Exception => e
      raise CsvNormalizationException.new(columnkey, row[columnkey],
                                          e.message)
    end
  end

  # read a line from `in_io` and ensure the line is UTF-8 encoded,
  # replacing any undefined or invalid characters with the Unicode
  # Replacement Character
  def get_utf8_normalized_line(in_io)
    in_io.gets&.encode("utf-8", { undef: :replace,
                                  invalid: :replace,
                                  replace: "\uFFFD" })
  end

  def normalize(in_io, out_io)
    headers = nil
    while line = get_utf8_normalized_line(in_io)
      if !headers
        headers = CSV.parse_line(line)
        out_io.puts(line.strip)
        next
      end
      begin
        row = CSV.parse_line(line, headers: headers)
        normalize_column(row, 'Timestamp', :normalize_timestamp_string)
        normalize_column(row, 'ZIP', :normalize_zip_string)
        normalize_column(row, 'FullName', :normalize_fullname_string)
        normalize_column(row, 'FooDuration', :normalize_duration_string)
        normalize_column(row, 'BarDuration', :normalize_duration_string)
        row['TotalDuration'] = row['FooDuration'] + row['BarDuration']
        out_io.write(CSV.generate_line(row, headers: headers))
      rescue CsvNormalizationException => cne
        logger.warn cne.message
      rescue Exception => e
        logger.warn "Unhandled normalization error"
        logger.warn e
      end
    end
  end
end

if $0 == __FILE__
  CsvNormalizer.new.normalize($stdin, $stdout)
end
