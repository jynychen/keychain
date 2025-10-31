#!/bin/bash
# Test script for bash completion functionality
# Tests that completion works correctly across different environments
# Returns 0 on success, 1 on any failure
# Usage: ./scripts/test-completion.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXIT_CODE=0

echo "=== Bash Completion Test ==="
echo

# Source the completion script
echo "1. Sourcing completion script..."
if ! source "$REPO_DIR/completions/keychain.bash" 2>/dev/null; then
    echo "   ERROR: Failed to source completion script"
    exit 1
fi
echo "   Done"
echo

# Test if __keychain_command_line_options works
echo "2. Testing __keychain_command_line_options function..."
opts_output=$(__keychain_command_line_options)
if [ -z "$opts_output" ]; then
    echo "   ERROR: Function returned empty string"
    echo "   (This usually means 'keychain' is not in PATH or is keychain.sh instead of generated keychain)"
    EXIT_CODE=1
else
    echo "   SUCCESS: Function returned options"
    echo "   First 5 options: $(echo "$opts_output" | awk '{for(i=1;i<=5;i++) print $i}' | tr '\n' ' ')"
fi
echo

# Test the array form
echo "3. Testing options as array..."
# shellcheck disable=SC2207
opts_array=( $(__keychain_command_line_options) )
echo "   Array has ${#opts_array[@]} elements"
if [ ${#opts_array[@]} -eq 0 ]; then
    echo "   ERROR: Array is empty"
    EXIT_CODE=1
else
    echo "   SUCCESS: First 5 elements: ${opts_array[*]:0:5}"
fi
echo

# Simulate completion for "keychain -"
echo "4. Simulating completion for 'keychain -<tab>'..."
COMP_WORDS=(keychain -)
COMP_CWORD=1
_keychain
echo "   COMPREPLY has ${#COMPREPLY[@]} items"
if [ ${#COMPREPLY[@]} -eq 0 ]; then
    echo "   ERROR: No completions returned"
    EXIT_CODE=1
else
    echo "   SUCCESS: First 5 completions:"
    for i in "${COMPREPLY[@]:0:5}"; do
        echo "     - $i"
    done
fi
echo

# Check which keychain is being found
echo "5. Checking keychain executable location..."
if command -v keychain >/dev/null 2>&1; then
    echo "   Found: $(command -v keychain)"
elif [ -x "$REPO_DIR/keychain" ]; then
    echo "   Found: $REPO_DIR/keychain (local)"
elif [ -x "$REPO_DIR/keychain.sh" ]; then
    echo "   WARNING: Only found keychain.sh (needs 'make' to generate full keychain)"
else
    echo "   WARNING: keychain not found in PATH or local directory"
fi
echo

# Test calling keychain --help
echo "6. Testing 'keychain --help' output..."
if keychain --help >/dev/null 2>&1; then
    echo "   SUCCESS: keychain --help works"
    first_line=$(keychain --help 2>&1 | head -1)
    if [ -n "$first_line" ]; then
        echo "   First line: $first_line"
    fi
else
    echo "   ERROR: keychain --help failed"
    EXIT_CODE=1
fi
echo

echo "=== Test Complete ==="
if [ $EXIT_CODE -eq 0 ]; then
    echo "Result: SUCCESS - All tests passed"
else
    echo "Result: FAILURE - Some tests failed"
fi

exit $EXIT_CODE
