#!/bin/bash

# function to execute before each test (e.g., to setup the environment)
function setUp() {

  function ciop-log {
   echo $@
  }

  export -f ciop-log

}

# function to execute after each test (e.g., to clean up the environment)
#function tearDown() {}
