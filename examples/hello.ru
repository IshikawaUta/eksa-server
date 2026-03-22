# examples/hello.ru
# Jalankan dengan: eksa-server examples/hello.ru

run lambda { |env|
  [200, {"Content-Type" => "text/html"}, ["<h1>Halo dari EksaServer!</h1><p>Ini adalah aplikasi Rack paling sederhana.</p>"]]
}
