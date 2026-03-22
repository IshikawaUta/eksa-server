# examples/static.ru
# Jalankan dengan: eksa-server examples/static.ru
# Letakkan file di examples/public/

use Rack::Static, 
  urls: [""],
  root: File.expand_path("public", __dir__),
  index: "index.html"

run lambda { |env|
  [404, {"Content-Type" => "text/html"}, ["<h1>404 Not Found</h1>"]]
}
