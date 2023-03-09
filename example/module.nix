{
  secrets.sopsFile = ./hosts/test.secrets.json;
  secrets.sopsFileLocal = "$(pwd)/hosts/test.secrets.json";

  secrets.files = let inherit (config.secrets) generators; in {
    mysecret.generator = generators.random "mysecret" "alphanum" 16;
  };
}
