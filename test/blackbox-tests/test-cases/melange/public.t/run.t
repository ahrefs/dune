Test the public libs flow when using `melange.emit` stanza

Cmj rules should include --bs-package-output
  $ dune rules my_project/app/.app.objs/melange/app.cmj |
  > grep -e "--bs-package-output" --after-context=1
      --bs-package-output
      .

Cmj rules should include --bs-package-name
  $ dune rules my_project/app/.app.objs/melange/app.cmj |
  > grep -e "--bs-package-name" --after-context=1
      --bs-package-name
      pkg.app

  $ output=my_project/output

Library JS is copied from a shared emission; its rule should include
--bs-module-type and --bs-package-name
  $ dune rules -r $output/node_modules/pkg.app/b.js |
  > grep -e "--bs-module-type" --after-context=3
      --bs-module-type
      commonjs
      --bs-package-name
      pkg

Build js files
  $ dune build @mel

Path to app_B is non-relative (broken)
  $ node _build/default/$output/my_project/c.js
  buy it

  $ dune clean
  $ dune build @all

