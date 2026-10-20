#!/usr/bin/env python3
"""Run a fixed worker group, forward signals, and fail the container on child exit."""
import json
import os
import signal
import subprocess
import sys
import time


def run(specifications):
    processes = []
    stopping = [False]

    def stop(_signum=None, _frame=None):
        stopping[0] = True
        for process in processes:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    result = 0
    try:
        for specification in specifications:
            environment = dict(os.environ)
            environment['CIVICSIGNAL_PROCESS_MEMORY_MB'] = str(specification['memory'])
            environment['CIVICSIGNAL_PROCESS_CPU_COUNT'] = '1'
            print('Starting ' + specification['name'], flush=True)
            processes.append(subprocess.Popen(specification['command'], env=environment, start_new_session=True))
        while not stopping[0]:
            for specification, process in zip(specifications, processes):
                if process.poll() is not None:
                    print(specification['name'] + ' exited; restarting the worker group', file=sys.stderr, flush=True)
                    result = 1
                    stop()
                    break
            time.sleep(0.25)
    finally:
        stop()
        deadline = time.monotonic() + 20
        while any(process.poll() is None for process in processes) and time.monotonic() < deadline:
            time.sleep(0.1)
        for process in processes:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait()
    return result


if __name__ == '__main__':
    with open(sys.argv[1]) as source:
        sys.exit(run(json.load(source)))
