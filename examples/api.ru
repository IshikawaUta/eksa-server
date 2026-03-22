# examples/api.ru
# Jalankan dengan: eksa-server examples/api.ru
require 'json'

run lambda { |env|
  data = {
    message: "Halo! Ini adalah contoh API JSON",
    server: "EksaServer v2",
    timestamp: Time.now.to_i,
    status: "online"
  }
  
  [200, {"Content-Type" => "application/json"}, [data.to_json]]
}
