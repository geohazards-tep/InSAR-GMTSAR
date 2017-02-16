#!/bin/bash

for test in $( ls tests.d/t* )
do
  /bin/bash ${test}
done
