{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "lazymc";
  version = "0.2.10";

  src = fetchFromGitHub {
    owner = "timvisee";
    repo = "lazymc";
    rev = "v${version}";
    hash = "sha256-IObLjxuMJDjZ3M6M1DaPvmoRqAydbLKdpTQ3Vs+B9Oo=";
  };

  cargoHash = "sha256-Tx+Bof4NtVd7AlYMS6veLiT/9vBXPIRVpMecoW7SpfM=";

  meta = with lib; {
    description = "Put your Minecraft server to rest when idle";
    homepage = "https://github.com/timvisee/lazymc";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ h7x4 ];
    platforms = platforms.linux;
    mainProgram = "lazymc";
  };
}
