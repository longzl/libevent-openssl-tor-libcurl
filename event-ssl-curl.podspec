Pod::Spec.new do |s|
  s.name         = "event-ssl-curl"
  s.version      = "1.0.12"
  s.summary      = "event-ssl-curl library."
  s.description  = <<-DESC
                   libevent, openssl, libcurl, tor, c-ares.
                   DESC
  s.homepage     = "https://github.com/HydraFramework/libevent-openssl-tor-libcurl"
  s.license      = "MIT"
  s.author       = { "samchang" => "sam.chang@me.com" }
  s.platform     = :ios, "6.0.0"
  s.source       = { :git => "http://git.luafan.com/libevent-openssl-tor-libcurl.git", :tag => "v1.0.12" }
  s.header_mappings_dir = "include"
  s.libraries     = "stdc++.6.0.9"
  s.source_files  = "include", "include/**/*.{h}", "sqlcipher/*.{h,c}"
  s.compiler_flags  = '-DSQLITE_HAS_CODEC'

  s.ios.vendored_libraries = 'lib/*.a'
  s.xcconfig = { "HEADER_SEARCH_PATHS" => "$(SRCROOT)/event-ssl-curl/include"}
end
