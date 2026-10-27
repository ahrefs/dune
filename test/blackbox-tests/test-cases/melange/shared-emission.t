Library modules are emitted once per emission configuration in
_build/default/.melange/<digest> and copied into every melange.emit target
that uses them.

  $ cat > dune-project <<EOF
  > (lang dune 3.8)
  > (using melange 0.1)
  > (package (name pkg))
  > EOF

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

  $ dune build @mel --display short 2>&1 | grep -E 'melc .*\.m?js$' |
  > sed -E 's/[0-9a-f]{32}/$DIGEST/' | sort
          melc .melange/$DIGEST/node_modules/pkg.__private__.privpkg/privpkg.js
          melc .melange/$DIGEST/node_modules/pkg.__private__.privpkg/privpkg.mjs
          melc .melange/$DIGEST/node_modules/pkg.__private__.privpkg/privpkg.mjs
          melc .melange/$DIGEST/node_modules/pkg.pub/base.js
          melc .melange/$DIGEST/node_modules/pkg.pub/base.mjs
          melc .melange/$DIGEST/node_modules/pkg.pub/base.mjs
          melc .melange/$DIGEST/node_modules/pkg.pub/sub/pub_sub.js
          melc .melange/$DIGEST/node_modules/pkg.pub/sub/pub_sub.mjs
          melc .melange/$DIGEST/node_modules/pkg.pub/sub/pub_sub.mjs
          melc .melange/$DIGEST/priv/priv.js
          melc .melange/$DIGEST/priv/priv.mjs
          melc .melange/$DIGEST/priv/priv.mjs
          melc a/out/a/main.js
          melc a/out/a/main.mjs
          melc b/c/out/b/c/main.mjs
          melc d/out/d/main.mjs
          melc e/out/e/main.mjs
          melc e/out/node_modules/pkg.__private__.privpkg/privpkg.mjs
          melc e/out/node_modules/pkg.pub/base.mjs
          melc e/out/node_modules/pkg.pub/sub/pub_sub.mjs
          melc e/out/priv/priv.mjs

One directory per library and configuration: 3 libraries times es6/mjs,
commonjs/js and the flags of d/.

  $ ls _build/default/.melange | wc -l | tr -d ' '
  9

Every target has the same files, and the shared ones are identical.

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
  $ dune build @mel --display short 2>&1 | grep -E 'melc .*\.m?js$' |
  > sed -E 's/[0-9a-f]{32}/$DIGEST/' | sort
          melc .melange/$DIGEST/node_modules/pkg.pub/base.js
          melc .melange/$DIGEST/node_modules/pkg.pub/base.mjs
          melc .melange/$DIGEST/node_modules/pkg.pub/base.mjs
          melc .melange/$DIGEST/node_modules/pkg.pub/sub/pub_sub.js
          melc .melange/$DIGEST/node_modules/pkg.pub/sub/pub_sub.mjs
          melc .melange/$DIGEST/node_modules/pkg.pub/sub/pub_sub.mjs
          melc .melange/$DIGEST/priv/priv.js
          melc .melange/$DIGEST/priv/priv.mjs
          melc .melange/$DIGEST/priv/priv.mjs
          melc a/out/a/main.js
          melc a/out/a/main.mjs
          melc b/c/out/b/c/main.mjs
          melc d/out/d/main.mjs
          melc e/out/e/main.mjs
          melc e/out/node_modules/pkg.pub/base.mjs
          melc e/out/node_modules/pkg.pub/sub/pub_sub.mjs
          melc e/out/priv/priv.mjs
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
  $ dune build @std --display short 2>&1 | grep -c 'melc .*/out/node_modules'
  0
  [1]
  $ node _build/default/f/out/f/main.mjs
  1
  $ diff -r _build/default/f/out/node_modules _build/default/g/out/node_modules
