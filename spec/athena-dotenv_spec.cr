require "./spec_helper"

struct DotEnvTest < ASPEC::TestCase
  @[DataProvider("env_data_with_format_errors")]
  def test_parse_with_format_error(data : String, error_message : String) : Nil
    dotenv = Athena::Dotenv.new

    expect_raises Athena::Dotenv::Exceptions::Format, error_message do
      dotenv.parse data
    end
  end

  def env_data_with_format_errors : Array
    tests = [
      {"FOO=BAR BAZ", "A value containing spaces must be surrounded by quotes in '.env' at line 1.\n...FOO=BAR BAZ...\n             ^ line 1 offset 11"},
    ] of {String, String}

    tests
  end
end
