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

class IoEncodingNormalizer
  def initialize(io, encoding, encode_options)
    @io = io
    @encoding = encoding
    @encode_options = encode_options
  end

  def gets(sep)
    x = @io.gets(sep)&.encode(@encoding, @encode_options)
#    STDERR.puts "DEBUG:x:#{x}"
    return x
  end

  def method_missing(m, *args, &block)
    @io.send(m, args, block)
  end
end

class CsvNormalizer

  SECONDS_IN_HOUR = 3600
  SECONDS_IN_MINUTE = 60
  DURATION_RE = Regexp.new('(\d{1,2}):(\d{2}):(\d{2})\.(\d+)')

  attr_accessor :logger
  def initialize(logger = Logger.new($stderr))
    self.logger = logger
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

  # Convert the provided `namestr` to upper case.
  def normalize_fullname_string(namestr)
    namestr.upcase
  end

  # Convert the provided `durationstr` in the format HH:MM:SS.MS into
  # a float representing the fractional seconds. Raise an exception if
  # the string cannot be parsed
  def normalize_duration_string(durationstr)
    if m = DURATION_RE.match(durationstr)
      Integer(m[1]) * SECONDS_IN_HOUR +
        Integer(m[2]) * SECONDS_IN_MINUTE +
        Integer(m[3]) +
        Float(m[4])
    else
      raise "Cannot parse duration"
    end
  end

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

  def normalize(in_io, out_io)
    nin_io = IoEncodingNormalizer.new(in_io, "utf-8", { undef: :replace,
                                                        invalid: :replace,
                                                        replace: "\uFFFD" })
    in_csv = CSV.new(nin_io, headers: true, row_sep:"\r\n")
    STDERR.puts "DEBUG:" + in_csv.shift.inspect
    out_csv = CSV.new(out_io, write_headers: true)
    in_csv.each.with_index do |row,i|
      if i == 0
        out_csv << in_csv.headers
      end
      begin
        normalize_column(row, 'Timestamp', :normalize_timestamp_string)
        normalize_column(row, 'ZIP', :normalize_zip_string)
        normalize_column(row, 'FullName', :normalize_fullname_string)
        normalize_column(row, 'FooDuration', :normalize_duration_string)
        normalize_column(row, 'BarDuration', :normalize_duration_string)
        row['TotalDuration'] = row['FooDuration'] + row['BarDuration']
        out_csv << row
      rescue CsvNormalizationException => cne
        logger.warn cne.message
      rescue Exception => e
        logger.warn "Unhandled normalization error"
        logger.warn e
      end
      out_io.flush
    end
  end
end

if $0 == __FILE__
  CsvNormalizer.new.normalize($stdin, $stdout)
end
