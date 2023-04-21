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
      {"FOO BAR=BAR", "Whitespace characters are not supported after the variable name in '.env' at line 1.\n...FOO BAR=BAR...\n     ^ line 1 offset 3"},
      {"FOO", "Missing = in the environment variable declaration in '.env' at line 1.\n...FOO...\n     ^ line 1 offset 3"},
      {"FOO=\"foo", "Missing quote to end the value in '.env' at line 1.\n...FOO=\"foo...\n          ^ line 1 offset 8"},
      {"FOO='foo", "Missing quote to end the value in '.env' at line 1.\n...FOO='foo...\n          ^ line 1 offset 8"},
      {"FOO=\"foo\nBAR=\"bar\"", "Missing quote to end the value in '.env' at line 1.\n...FOO=\"foo\\nBAR=\"bar\"...\n                     ^ line 1 offset 18"},
      # # {"FOO=\'foo'."\n", "Missing quote to end the value in \".env\" at line 1.\n...FOO='foo\\n...\n            ^ line 1 offset 9"},
      # {"export FOO", "Unable to unset an environment variable in \".env\" at line 1.\n...export FOO...\n            ^ line 1 offset 10"},
      # {"FOO=${FOO", "Unclosed braces on variable expansion in \".env\" at line 1.\n...FOO=${FOO...\n           ^ line 1 offset 9"},
      # {"FOO= BAR", "Whitespace are not supported before the value in \".env\" at line 1.\n...FOO= BAR...\n      ^ line 1 offset 4"},
      # {"Стасян", "Invalid character in variable name in \".env\" at line 1.\n...Стасян...\n  ^ line 1 offset 0"},
      # {"FOO!", "Missing = in the environment variable declaration in \".env\" at line 1.\n...FOO!...\n     ^ line 1 offset 3"},
      # {"FOO=$(echo foo", "Missing closing parenthesis. in \".env\" at line 1.\n...FOO=$(echo foo...\n                ^ line 1 offset 14"},
      # # {"FOO=$(echo foo'."\n", "Missing closing parenthesis. in \".env\" at line 1.\n...FOO=$(echo foo\\n...\n                ^ line 1 offset 14"},
      # {"FOO=\nBAR=${FOO:-'a{a}a}", "Unsupported character \"'\" found in the default value of variable \"$FOO\". in \".env\" at line 2.\n...\\nBAR=${FOO:-'a{a}a}...\n                       ^ line 2 offset 24"},
      # {"FOO=\nBAR=${FOO:-a$a}", "Unsupported character \"$\" found in the default value of variable \"$FOO\". in \".env\" at line 2.\n...FOO=\\nBAR=${FOO:-a$a}...\n                       ^ line 2 offset 20"},
      # {"FOO=\nBAR=${FOO:-a\"a}", "Unclosed braces on variable expansion in \".env\" at line 2.\n...FOO=\\nBAR=${FOO:-a\"a}...\n                    ^ line 2 offset 17"},

    ] of {String, String}

    tests
  end
end
