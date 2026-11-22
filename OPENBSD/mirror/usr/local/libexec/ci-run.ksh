#!/bin/ksh
# vm23 is a production host, not a test-runner or build host.
echo "ci-run: refused - run the selected app's bin/ci on the operator workstation." >&2
exit 69
