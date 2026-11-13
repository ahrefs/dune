Library modules are emitted once per emission configuration in
_build/default/.melange/<digest> and copied into every melange.emit target
that uses them.

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
attached to a package.

  $ mkdir -p pub/sub priv privpkg
  $ cat > pub/dune <<EOF
  > (include_subdirs unqualified)
  > (library
  >  (name pub)
  >  (public_name pkg.pub)
  >  (modes melange))
  > EOF
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
  .melange/$DIGEST/node_modules/pkg.__private__.privpkg/privpkg.js
  .melange/$DIGEST/node_modules/pkg.__private__.privpkg/privpkg.mjs
  .melange/$DIGEST/node_modules/pkg.__private__.privpkg/privpkg.mjs
  .melange/$DIGEST/node_modules/pkg.pub/base.js
  .melange/$DIGEST/node_modules/pkg.pub/base.mjs
  .melange/$DIGEST/node_modules/pkg.pub/base.mjs
  .melange/$DIGEST/node_modules/pkg.pub/sub/pub_sub.js
  .melange/$DIGEST/node_modules/pkg.pub/sub/pub_sub.mjs
  .melange/$DIGEST/node_modules/pkg.pub/sub/pub_sub.mjs
  .melange/$DIGEST/priv/priv.js
  .melange/$DIGEST/priv/priv.mjs
  .melange/$DIGEST/priv/priv.mjs
  a/out/a/main.js
  a/out/a/main.mjs
  b/c/out/b/c/main.mjs
  d/out/d/main.mjs
  e/out/e/main.mjs
  e/out/node_modules/pkg.__private__.privpkg/privpkg.mjs
  e/out/node_modules/pkg.pub/base.mjs
  e/out/node_modules/pkg.pub/sub/pub_sub.mjs
  e/out/priv/priv.mjs

One directory per library and configuration: 3 libraries times es6/mjs,
commonjs/js and the flags of d/. The stanza in e/ has its own environment and
emits its own copy.

  $ ls _build/default/.melange | wc -l | tr -d ' '
  9

A no-op rebuild runs no melc.

  $ dune build @mel
  $ melc_outputs

The copies are identical to the files that e/ emits on its own.

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

Promotion still applies to the copies.

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

Changing a library re-emits it once per configuration and updates every target.

  $ echo 'let x = "PUB"' > pub/base.ml
  $ dune build @mel
  $ melc_outputs
  .melange/$DIGEST/node_modules/pkg.pub/base.js
  .melange/$DIGEST/node_modules/pkg.pub/base.mjs
  .melange/$DIGEST/node_modules/pkg.pub/base.mjs
  .melange/$DIGEST/node_modules/pkg.pub/sub/pub_sub.js
  .melange/$DIGEST/node_modules/pkg.pub/sub/pub_sub.mjs
  .melange/$DIGEST/node_modules/pkg.pub/sub/pub_sub.mjs
  .melange/$DIGEST/priv/priv.js
  .melange/$DIGEST/priv/priv.mjs
  .melange/$DIGEST/priv/priv.mjs
  a/out/a/main.js
  a/out/a/main.mjs
  b/c/out/b/c/main.mjs
  d/out/d/main.mjs
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

A library used by a single stanza is shared too, and the stdlib is shared
between stanzas that emit it.

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
  [1]
  $ node _build/default/f/out/f/main.mjs
  1
  $ diff -r _build/default/f/out/node_modules _build/default/g/out/node_modules
