# The page must not contain the daScript compiler, parser or module
# registrations (they would bring back the 30 MB interpreter build).
file(READ "${MAP_FILE}" symbols)
if(symbols MATCHES "compileDaScript|das2?_yyparse|register_Module_|libDaScript[.:]")
    message(FATAL_ERROR "Standalone link contains compiler / module registrations: ${MAP_FILE}")
endif()
message(STATUS "Standalone link checked: no compiler or module registrations")
