# encoding: UTF-8

require 'minitest/autorun'
require 'csv_normalizer'

class TestCsvNormalizer < Minitest::Test

  class TestLogger
    attr_accessor :logs
    def initialize(*args)
      @logs = []
    end

    def method_missing(*args)
      @logs << args
    end
  end

  def setup
    @test_logger = TestLogger.new
    @norma = CsvNormalizer.new(@test_logger)
  end

  def test_normalize_timestamp_string
    assert_equal '2011-04-01T14:00:00-04:00',
      @norma.normalize_timestamp_string('4/1/11 11:00:00 AM')
    assert_equal '2018-01-02T02:59:59-05:00',
      @norma.normalize_timestamp_string('1/1/18 11:59:59 PM')
    assert_raises ArgumentError do
      @norma.normalize_timestamp_string('bad')
    end
  end

  def test_normalize_zip_string
    assert_equal '12345', @norma.normalize_zip_string('12345')
    assert_equal '00005', @norma.normalize_zip_string('5')
    assert_raises ArgumentError do
      @norma.normalize_zip_string('bad')
    end
  end

  def test_normalize_fullname_string
    assert_equal 'HIYA', @norma.normalize_fullname_string('hIyA')
    if RUBY_VERSION < '2.4'
      skip "Cannot fully test normalizing fullname"
    end
    assert_equal 'TÜRKIYE', @norma.normalize_fullname_string('Türkiye')
    assert_nil @norma.normalize_fullname_string(nil)
  end

  def test_normalize_duration_string
    assert_equal 1.234, @norma.normalize_duration_string('0:00:01.234')
    assert_equal 3600 + 60 + 1.01,
      @norma.normalize_duration_string('1:01:01.01')
    assert_raises RuntimeError do
      @norma.normalize_duration_string('bad')
    end
  end

  def test_normalize_column
    raw_data = {'zip' => '5', 'a' => 'b'}
    expected_data = {'zip' => '00005', 'a' => 'b'}
    @norma.normalize_column(raw_data, 'zip', :normalize_zip_string)
    assert_equal expected_data, raw_data

    raw_data = {'zip' => 'b'}
    assert_raises CsvNormalizationException do
      @norma.normalize_column(raw_data, 'zip', :normalize_zip_string)
    end
  end

  def test_get_utf8_normalize_line
    assert_nil @norma.get_utf8_normalized_line(StringIO.new)
    assert_equal "κόσμε\r\n",
      @norma.get_utf8_normalized_line(StringIO.new("κόσμε\r\nabc\r\n"))
    bogon_io = StringIO.new("abc\u0080\u00BF\r\n".
                            force_encoding("ASCII-8BIT"))
    assert_equal "abc\uFFFD\uFFFD\uFFFD\uFFFD\r\n",
      @norma.get_utf8_normalized_line(bogon_io)
  end

  def test_normalize
    headers = 'Timestamp,Address,ZIP,FullName,FooDuration,BarDuration,TotalDuration,Notes'
    row1 = '4/1/11 11:00:00 AM,"123 4th St, Anywhere, AA",94121,Monkey Alberto,1:23:32.123,1:32:33.123,zzsasdfa,I am the very model of a modern major general'
    badrow = "13/13/10 4:48:12 PM,Høøük¡,1231,Sleeper Service,1:23:32.123,1:32:33.123,zzsasdfa,2/1/22"
    tin = StringIO.new([headers, row1, badrow].join("\r\n"))
    tout = StringIO.new

    @norma.normalize(tin, tout)
    tout.rewind
    assert_equal "#{headers}\n", tout.gets
    nrow1 = '2011-04-01T14:00:00-04:00,"123 4th St, Anywhere, AA",94121,MONKEY ALBERTO,5012.123,5553.123,10565.246,I am the very model of a modern major general'
    assert_equal "#{nrow1}\n", tout.gets
    assert_nil tout.gets

    if RUBY_VERSION < '2.4'
      assert_match(/Possibly invalid upcasing of names/,
                   @test_logger.logs.first.last)
      # remove that entry
      @test_logger.logs.shift
    end
    assert_equal 1, @test_logger.logs.size
    assert_equal :warn, @test_logger.logs.first.first
    assert_match(/Error normalizing column 'Timestamp'/,
                 @test_logger.logs.first.last)
  end
end
