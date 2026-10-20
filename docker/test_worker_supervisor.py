import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


class SupervisorTest(unittest.TestCase):
    def start(self, commands):
        fixture = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
        json.dump([dict(name=str(index), command=command, memory=512) for index, command in enumerate(commands)], fixture)
        fixture.close()
        self.addCleanup(lambda: Path(fixture.name).unlink())
        process = subprocess.Popen([sys.executable, str(Path(__file__).with_name('worker-supervisor.py')), fixture.name], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        return process

    def test_child_exit_fails_group_and_stops_other_children(self):
        process = self.start([[sys.executable, '-c', 'pass'], [sys.executable, '-c', 'import time; time.sleep(60)']])
        _, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 1)
        self.assertIn('exited', stderr)

    def test_sigterm_shuts_down_group(self):
        process = self.start([[sys.executable, '-c', 'import time; time.sleep(60)']])
        self.assertIn('Starting', process.stdout.readline())
        time.sleep(0.1)
        process.send_signal(signal.SIGTERM)
        process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0)


if __name__ == '__main__':
    unittest.main()
