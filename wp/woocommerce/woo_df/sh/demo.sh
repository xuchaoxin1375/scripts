#! /bin/bash
R="old"
echo "before:R=$R"
fun() {
    local -n var="$1"
    local value="$2"
    var="$value"
    echo "$var" >/dev/null
}

fun R "new"
echo "later:R=$R"