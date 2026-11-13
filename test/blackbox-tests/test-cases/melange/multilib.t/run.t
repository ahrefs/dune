Compilation using melange with a library
The rules should include cmjs of dependencies as well.

Make sure no byte folders are included.

  $ dune rules -r --format=json multilib/x/m_2.js |
  > jq_dune -r 'runRulesMatchingTarget("x/m_2.js") | ruleActionRunArgv | .[] | select(contains(".objs"))'
  x/.x.objs/melange
  lib/.lib.objs/melange
  x/.x.objs/melange/x__M_2.cmj

Test resulting file

  $ dune build @mel
  $ node ./_build/default/multilib/c.js
  done
