require "#{ENV['TM_SUPPORT_PATH']}/private/track_usage.rb"

# escape text to make it useable in a shell script as one "word" (string)
def e_sh(str)
	str.to_s.gsub(/(?=[^a-zA-Z0-9_.\/\-\x7F-\xFF\n])/n, '\\').gsub(/\n/, "'\n'").sub(/^$/, "''")
end

# escape text for use in a TextMate snippet
def e_sn(str)
	str.to_s.gsub(/(?=[$`\\])/, '\\')
end

# escape text for use in a TextMate snippet placeholder
def e_snp(str)
	str.to_s.gsub(/(?=[$`\\}])/, '\\')
end

# escape text for use in an AppleScript string
def e_as(str)
	str.to_s.gsub(/(?=["\\])/, '\\')
end

# URL escape a string but preserve slashes
def e_url(str)
  str.gsub(/([^a-zA-Z0-9\/_.-]+)/n) do
    '%' + $1.unpack('H2' * $1.size).join('%').upcase
  end
end

# Make string suitable for display as HTML, preserve spaces.
def htmlize(str, opts = {})
  str = str.to_s.gsub("&", "&amp;").gsub("<", "&lt;")
  str = str.gsub(/\t+/, '<span style="white-space:pre;">\0</span>')
  str = str.gsub(/(^ +)|( )( +)/) { "#$2#{'&nbsp;' * ($1 || $3).length}" }
  if opts[:no_newline_after_br].nil?
    str.gsub("\n", "<br>\n")
  else
    str.gsub("\n", "<br>")
  end
end
