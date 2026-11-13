Several melange.emit stanzas use the same libraries. Each stanza emits its own
copy of every library module into its target.

  $ cat > dune-project <<EOF
  > (lang dune 3.8)
  > (using melange 0.1)
  > (package (name pkg))
  > EOF

melc_outputs lists the JS files written by melc in the last build.

  $ melc_outputs () {
  >   dune trace cat |
  >   jq_dune -r 'processes | .args | select(.prog | endswith("/melc")) | .target_files[]? | select(test("\\.m?js$"))' |
  >   sed -E 's#^_build/default/##; s#\.melange/[0-9a-f]+/#.melange/$DIGEST/#' | sort
  > }

A public library with a sub-directory, a private library and a private library
attached to a package. The public library has a runtime dependency.

  $ mkdir -p pub/sub priv privpkg
  $ cat > pub/dune <<EOF
  > (include_subdirs unqualified)
  > (library
  >  (name pub)
  >  (public_name pkg.pub)
  >  (modes melange)
  >  (melange.runtime_deps asset.txt))
  > EOF
  $ echo hello > pub/asset.txt
  $ echo 'let x = "pub"' > pub/base.ml
  $ echo 'let y = Base.x ^ "-sub"' > pub/sub/pub_sub.ml
  $ cat > priv/dune <<EOF
  > (library (name priv) (modes melange) (libraries pub privpkg))
  > EOF
  $ echo 'let z = Pub.Pub_sub.y ^ Privpkg.w' > priv/priv.ml
  $ cat > privpkg/dune <<EOF
  > (library (name privpkg) (package pkg) (modes melange))
  > EOF
  $ echo 'let w = "-privpkg"' > privpkg/privpkg.ml

Three stanzas in different directories share the es6/mjs configuration. The
first one also asks for commonjs, and is promoted. The fourth one has its own
flags, the fifth one its own environment.

  $ mkdir -p a b/c d e
  $ cat > a/dune <<EOF
  > (melange.emit
  >  (target out)
  >  (alias mel)
  >  (emit_stdlib false)
  >  (promote (until-clean))
  >  (libraries priv)
  >  (module_systems (es6 mjs) (commonjs js)))
  > EOF
  $ cat > b/c/dune <<EOF
  > (melange.emit
  >  (target out)
  >  (alias mel)
  >  (emit_stdlib false)
  >  (libraries priv)
  >  (module_systems (es6 mjs)))
  > EOF
  $ cat > d/dune <<EOF
  > (melange.emit
  >  (target out)
  >  (alias mel)
  >  (emit_stdlib false)
  >  (compile_flags :standard -w -a)
  >  (libraries priv)
  >  (module_systems (es6 mjs)))
  > EOF
  $ cat > e/dune <<EOF
  > (env (_ (env-vars (FOO bar))))
  > (melange.emit
  >  (target out)
  >  (alias mel)
  >  (emit_stdlib false)
  >  (libraries priv)
  >  (module_systems (es6 mjs)))
  > EOF
  $ for d in a b/c d e; do echo 'let () = Js.log Priv.z' > $d/main.ml; done

  $ dune build @mel
  $ melc_outputs
  a/out/a/main.js
  a/out/a/main.mjs
  a/out/node_modules/pkg.__private__.privpkg/privpkg.js
  a/out/node_modules/pkg.__private__.privpkg/privpkg.mjs
  a/out/node_modules/pkg.pub/base.js
  a/out/node_modules/pkg.pub/base.mjs
  a/out/node_modules/pkg.pub/sub/pub_sub.js
  a/out/node_modules/pkg.pub/sub/pub_sub.mjs
  a/out/priv/priv.js
  a/out/priv/priv.mjs
  b/c/out/b/c/main.mjs
  b/c/out/node_modules/pkg.__private__.privpkg/privpkg.mjs
  b/c/out/node_modules/pkg.pub/base.mjs
  b/c/out/node_modules/pkg.pub/sub/pub_sub.mjs
  b/c/out/priv/priv.mjs
  d/out/d/main.mjs
  d/out/node_modules/pkg.__private__.privpkg/privpkg.mjs
  d/out/node_modules/pkg.pub/base.mjs
  d/out/node_modules/pkg.pub/sub/pub_sub.mjs
  d/out/priv/priv.mjs
  e/out/e/main.mjs
  e/out/node_modules/pkg.__private__.privpkg/privpkg.mjs
  e/out/node_modules/pkg.pub/base.mjs
  e/out/node_modules/pkg.pub/sub/pub_sub.mjs
  e/out/priv/priv.mjs

A no-op rebuild runs no melc.

  $ dune build @mel
  $ melc_outputs

Every target has the same files, and the library files are identical.

  $ for d in a b/c d e; do
  >   (cd _build/default/$d/out && find . -name '*.mjs' -o -name '*.txt' | grep -v main | sort)
  > done | sort | uniq -c
        4 ./node_modules/pkg.__private__.privpkg/privpkg.mjs
        4 ./node_modules/pkg.pub/asset.txt
        4 ./node_modules/pkg.pub/base.mjs
        4 ./node_modules/pkg.pub/sub/pub_sub.mjs
        4 ./priv/priv.mjs
  $ for f in node_modules/pkg.__private__.privpkg/privpkg.mjs node_modules/pkg.pub/base.mjs node_modules/pkg.pub/sub/pub_sub.mjs priv/priv.mjs; do
  >   cmp _build/default/a/out/$f _build/default/b/c/out/$f
  >   cmp _build/default/a/out/$f _build/default/e/out/$f
  > done

  $ for d in a b/c d e; do node _build/default/$d/out/$d/main.mjs; done
  pub-sub-privpkg
  pub-sub-privpkg
  pub-sub-privpkg
  pub-sub-privpkg
  $ node _build/default/a/out/a/main.js
  pub-sub-privpkg

Library files are promoted with the stanza.

  $ find a/out -name '*.*js' | sort
  a/out/a/main.js
  a/out/a/main.mjs
  a/out/node_modules/pkg.__private__.privpkg/privpkg.js
  a/out/node_modules/pkg.__private__.privpkg/privpkg.mjs
  a/out/node_modules/pkg.pub/base.js
  a/out/node_modules/pkg.pub/base.mjs
  a/out/node_modules/pkg.pub/sub/pub_sub.js
  a/out/node_modules/pkg.pub/sub/pub_sub.mjs
  a/out/priv/priv.js
  a/out/priv/priv.mjs

Changing a library re-emits it in every target.

  $ echo 'let x = "PUB"' > pub/base.ml
  $ dune build @mel
  $ melc_outputs
  a/out/a/main.js
  a/out/a/main.mjs
  a/out/node_modules/pkg.pub/base.js
  a/out/node_modules/pkg.pub/base.mjs
  a/out/node_modules/pkg.pub/sub/pub_sub.js
  a/out/node_modules/pkg.pub/sub/pub_sub.mjs
  a/out/priv/priv.js
  a/out/priv/priv.mjs
  b/c/out/b/c/main.mjs
  b/c/out/node_modules/pkg.pub/base.mjs
  b/c/out/node_modules/pkg.pub/sub/pub_sub.mjs
  b/c/out/priv/priv.mjs
  d/out/d/main.mjs
  d/out/node_modules/pkg.pub/base.mjs
  d/out/node_modules/pkg.pub/sub/pub_sub.mjs
  d/out/priv/priv.mjs
  e/out/e/main.mjs
  e/out/node_modules/pkg.pub/base.mjs
  e/out/node_modules/pkg.pub/sub/pub_sub.mjs
  e/out/priv/priv.mjs
  $ for d in a b/c d e; do node _build/default/$d/out/$d/main.mjs; done
  PUB-sub-privpkg
  PUB-sub-privpkg
  PUB-sub-privpkg
  PUB-sub-privpkg
  $ node a/out/a/main.mjs
  PUB-sub-privpkg

Two stanzas that emit the stdlib each emit their own copy of it.

  $ mkdir f g
  $ cat > f/dune <<EOF
  > (melange.emit (target out) (alias std) (libraries pub) (module_systems (es6 mjs)))
  > EOF
  $ cat > g/dune <<EOF
  > (melange.emit (target out) (alias std) (libraries pub) (module_systems (es6 mjs)))
  > EOF
  $ echo 'let () = Js.log (List.length [Pub.Base.x])' > f/main.ml
  $ cp f/main.ml g/main.ml
  $ dune build @std
  $ melc_outputs | grep '/out/node_modules/' | cut -d / -f 1 | sort -u
  f
  g
  $ node _build/default/f/out/f/main.mjs
  1
  $ diff -r _build/default/f/out/node_modules _build/default/g/out/node_modules
