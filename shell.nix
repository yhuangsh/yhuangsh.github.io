{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    bundler
    jekyll
  ];
  shellHook = ''
    alias jserve='bundle exec jekyll serve --livereload --livereload-port 4400 -H'
  '';
}
