require "./spec_helper"

struct DotEnvTest < ASPEC::TestCase
  @[DataProvider("env_data")]
  def test_parse(data : String, expected : Hash(String, String)) : Nil
    Athena::Dotenv.new.parse(data).should eq expected
  end

  def env_data : Array
    tests = [
      # Backslashes
      {"FOO=foo\\\\bar", {"FOO" => "foo\\bar"}},
      {"FOO='foo\\\\bar'", {"FOO" => "foo\\\\bar"}},
      {"FOO=\"foo\\\\bar\"", {"FOO" => "foo\\bar"}},

      # Escaped backslash in front of variable
      {"BAR=bar\nFOO=foo\\\\$BAR", {"BAR" => "bar", "FOO" => "foo\\bar"}},
      {"BAR=bar\nFOO='foo\\\\$BAR'", {"BAR" => "bar", "FOO" => "foo\\\\$BAR"}},
      {"BAR=bar\nFOO=\"foo\\\\$BAR\"", {"BAR" => "bar", "FOO" => "foo\\bar"}},

      {"FOO=foo\\\\\\$BAR", {"FOO" => "foo\\$BAR"}},
      {"FOO='foo\\\\\\$BAR'", {"FOO" => "foo\\\\\\$BAR"}},
      {"FOO=\"foo\\\\\\$BAR\"", {"FOO" => "foo\\$BAR"}},

      # Spaces
      {"FOO=bar", {"FOO" => "bar"}},
      {" FOO=bar ", {"FOO" => "bar"}},
      {"FOO=", {"FOO" => ""}},
      {"FOO=\n\n\nBAR=bar", {"FOO" => "", "BAR" => "bar"}},
      {"FOO=  ", {"FOO" => ""}},
      {"FOO=\nBAR=bar", {"FOO" => "", "BAR" => "bar"}},

      # Newlines
      {"\n\nFOO=bar\r\n\n", {"FOO" => "bar"}},
      {"FOO=bar\r\nBAR=foo", {"FOO" => "bar", "BAR" => "foo"}},
      {"FOO=bar\rBAR=foo", {"FOO" => "bar", "BAR" => "foo"}},
      {"FOO=bar\nBAR=foo", {"FOO" => "bar", "BAR" => "foo"}},

      # Quotes
      {"FOO=\"bar\"\n", {"FOO" => "bar"}},
      {"FOO=\"bar'foo\"\n", {"FOO" => "bar'foo"}},
      {"FOO='bar'\n", {"FOO" => "bar"}},
      {"FOO='bar\"foo'\n", {"FOO" => "bar\"foo"}},
      {"FOO=\"bar\\\"foo\"\n", {"FOO" => "bar\"foo"}},
      {"FOO=\"bar\nfoo\"", {"FOO" => "bar\nfoo"}},
      {"FOO=\"bar\\rfoo\"", {"FOO" => "bar\rfoo"}}, # Double quote expands to real `\r`
      {"FOO='bar\nfoo'", {"FOO" => "bar\nfoo"}},
      {"FOO='bar\\rfoo'", {"FOO" => "bar\\rfoo"}}, # Single quotes keep the literal `\r`
      {"FOO='bar\nfoo'", {"FOO" => "bar\nfoo"}},
      {"FOO=\" FOO \"", {"FOO" => " FOO "}},
      {"FOO=\"  \"", {"FOO" => "  "}},
      {"PATH=\"c:\\\\\"", {"PATH" => "c:\\"}},
      {"FOO=\"bar\nfoo\"", {"FOO" => "bar\nfoo"}},
      {"FOO=BAR\\\"", {"FOO" => "BAR\""}},
      {"FOO=BAR\\'BAZ", {"FOO" => "BAR'BAZ"}},
      {"FOO=\\\"BAR", {"FOO" => "\"BAR"}},

      # Concatenated values
      {"FOO='bar''foo'\n", {"FOO" => "barfoo"}},
      {"FOO='bar '' baz'", {"FOO" => "bar  baz"}},
      {"FOO=bar\nBAR='baz'\"$FOO\"", {"FOO" => "bar", "BAR" => "bazbar"}},
      {"FOO='bar '\\'' baz'", {"FOO" => "bar ' baz"}},

      # Comments
      {"#FOO=bar\nBAR=foo", {"BAR" => "foo"}},
      {"#FOO=bar # Comment\nBAR=foo", {"BAR" => "foo"}},
      {"FOO='bar foo' # Comment", {"FOO" => "bar foo"}},
      {"FOO='bar#foo' # Comment", {"FOO" => "bar#foo"}},
      {"# Comment\r\nFOO=bar\n# Comment\nBAR=foo", {"FOO" => "bar", "BAR" => "foo"}},
      {"FOO=bar # Another comment\nBAR=foo", {"FOO" => "bar", "BAR" => "foo"}},
      {"FOO=\n\n# comment\nBAR=bar", {"FOO" => "", "BAR" => "bar"}},
      {"FOO=NOT#COMMENT", {"FOO" => "NOT#COMMENT"}},
      {"FOO=  # Comment", {"FOO" => ""}},

    ] of {String, Hash(String, String)}

    tests
  end

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
      {"FOO='foo\n", "Missing quote to end the value in '.env' at line 1.\n...FOO='foo\\n...\n            ^ line 1 offset 9"},
      {"export FOO", "Unable to unset an environment variable in '.env' at line 1.\n...export FOO...\n            ^ line 1 offset 10"},
      {"FOO=${FOO", "Unclosed braces on variable expansion in '.env' at line 1.\n...FOO=${FOO...\n           ^ line 1 offset 9"},
      {"FOO= BAR", "Whitespace is not supported before the value in '.env' at line 1.\n...FOO= BAR...\n      ^ line 1 offset 4"},
      {"Стасян", "Invalid character in variable name in '.env' at line 1.\n...Стасян...\n  ^ line 1 offset 0"},
      {"FOO!", "Missing = in the environment variable declaration in '.env' at line 1.\n...FOO!...\n     ^ line 1 offset 3"},
      {"FOO=$(echo foo", "Missing closing parenthesis in '.env' at line 1.\n...FOO=$(echo foo...\n                ^ line 1 offset 14"},
      {"FOO=$(echo foo\n", "Missing closing parenthesis in '.env' at line 1.\n...FOO=$(echo foo\\n...\n                ^ line 1 offset 14"},
      {"FOO=\nBAR=${FOO:-\\'a{a}a}", "Unsupported character ''' found in the default value of variable '$FOO' in '.env' at line 2.\n...\\nBAR=${FOO:-\\'a{a}a}...\n                       ^ line 2 offset 24"},
      {"FOO=\nBAR=${FOO:-a$a}", "Unsupported character '$' found in the default value of variable '$FOO' in '.env' at line 2.\n...FOO=\\nBAR=${FOO:-a$a}...\n                       ^ line 2 offset 20"},
      {"FOO=\nBAR=${FOO:-a\"a}", "Unclosed braces on variable expansion in '.env' at line 2.\n...FOO=\\nBAR=${FOO:-a\"a}...\n                    ^ line 2 offset 17"},
    ] of {String, String}

    {% if flag? :win32 %}
      tests << {"FOO=$((1dd2))", "Issue expanding a command (%s\n) in '.env' at line 1.\n...FOO=$((1dd2))...\n               ^ line 1 offset 13"}
    {% end %}

    tests
  end
end
