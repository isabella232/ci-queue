require 'minitest/reporters'
require 'builder'
require 'fileutils'

module Minitest
  module Queue
    class JUnitReporter < Minitest::Reporters::BaseReporter
      class XmlMarkup < ::Builder::XmlMarkup
        def trunc!(txt)
          txt.sub(/\n.*/m, '...')
        end
      end

      def initialize(report_path = 'log/junit.xml', options = {})
        super({})
        @report_path = File.absolute_path(report_path)
        @base_path = options[:base_path] || Dir.pwd
      end

      def report
        super

        suites = tests.group_by { |test| test.klass }

        xml = Builder::XmlMarkup.new(:indent => 2)
        xml.instruct!
        xml.test_suites do
          suites.each do |suite, tests|
            parse_xml_for(xml, suite, tests)
          end
        end
        FileUtils.mkdir_p(File.dirname(@report_path))
        File.open(@report_path, "w+") { |file| file << xml.target! }
      end

      private

      def parse_xml_for(xml, suite, tests)
        suite_result = analyze_suite(tests)
        file_path = Pathname.new(tests.first.source_location.first)
        base_path = Pathname.new(@base_path)
        relative_path = file_path.relative_path_from(base_path)

        xml.testsuite(:name => suite, :filepath => relative_path,
                      :skipped => suite_result[:skip_count], :failures => suite_result[:fail_count],
                      :errors => suite_result[:error_count], :tests => suite_result[:test_count],
                      :assertions => suite_result[:assertion_count], :time => suite_result[:time]) do
          tests.each do |test|
            lineno = test.source_location.last
            xml.testcase(:name => test.name, :lineno => lineno, :classname => suite, :assertions => test.assertions,
                         :time => test.time) do
              xml << xml_message_for(test) unless test.passed?
            end
          end
        end
      end

      def xml_message_for(test)
        xml = XmlMarkup.new(:indent => 2, :margin => 2)
        error = test.failure

        if test.skipped?
          xml.skipped(:type => test.name)
        elsif test.error?
          xml.error(:type => test.name, :message => xml.trunc!(error.message)) do
            xml.text!(message_for(test))
          end
        elsif test.failure
          xml.failure(:type => test.name, :message => xml.trunc!(error.message)) do
            xml.text!(message_for(test))
          end
        end
      end

      def message_for(test)
        suite = test.klass
        name = test.name
        error = test.failure

        if test.passed?
          nil
        elsif test.skipped?
          "Skipped:\n#{name}(#{suite}) [#{location(error)}]:\n#{error.message}\n"
        elsif test.failure
          "Failure:\n#{name}(#{suite}) [#{location(error)}]:\n#{error.message}\n"
        elsif test.error?
          "Error:\n#{name}(#{suite}):\n#{error.message}"
        end
      end

      def location(exception)
        last_before_assertion = ''
        exception.backtrace.reverse_each do |s|
          break if s =~ /in .(assert|refute|flunk|pass|fail|raise|must|wont)/
          last_before_assertion = s
        end
        last_before_assertion.sub(/:in .*$/, '')
      end

      def analyze_suite(tests)
        result = Hash.new(0)
        result[:time] = 0
        tests.each do |test|
          result[:"#{result(test)}_count"] += 1
          result[:assertion_count] += test.assertions
          result[:test_count] += 1
          result[:time] += test.time
        end
        result
      end
    end
  end
end
