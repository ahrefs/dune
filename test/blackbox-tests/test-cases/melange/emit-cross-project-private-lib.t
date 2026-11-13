A melange.emit stanza in project a uses a public library of project b, which
depends on a private library of b. The private library is emitted into the
target under its mangled name.

  $ mkdir -p a b/pub b/priv
  $ cat > dune-project <<EOF
  > (lang dune 3.8)
  > (using melange 0.1)
  > EOF
  $ cat > b/dune-project <<EOF
  > (lang dune 3.8)
  > (using melange 0.1)
  > (package (name b))
  > EOF
  $ cat > b/priv/dune <<EOF
  > (library (name priv) (package b) (modes melange))
  > EOF
  $ echo 'let v = "b"' > b/priv/priv.ml
  $ cat > b/pub/dune <<EOF
  > (library (name pub) (public_name b.pub) (modes melange) (libraries priv))
  > EOF
  $ echo 'let v = "pub"' > b/pub/pub.ml
  $ cat > a/dune <<EOF
  > (melange.emit (target out) (alias mel) (emit_stdlib false) (libraries b.pub))
  > EOF
  $ echo 'let () = Js.log Pub.v' > a/main.ml
  $ dune build @a/mel
  $ cat _build/default/a/out/node_modules/b.__private__.priv/priv.js | grep '"b"'
  const v = "b";

Project a also has a private library named priv. The target still gets the
one from project b.

  $ mkdir a/priv
  $ cat > a/priv/dune <<EOF
  > (library (name priv) (modes melange))
  > EOF
  $ echo 'let v = "a"' > a/priv/priv.ml
  $ dune build @a/mel
  $ cat _build/default/a/out/node_modules/b.__private__.priv/priv.js | grep '"b"'
  const v = "b";
