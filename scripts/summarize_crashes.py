"""Allowlisted crash codes and binary symbol names only; never raw diagnostics."""
import json
import re
from pathlib import Path


def summarize(report):
    exception = report.get('exception', {})
    termination = report.get('termination', {})
    allowed_types = {'EXC_CRASH', 'EXC_BAD_ACCESS', 'EXC_BREAKPOINT', 'EXC_RESOURCE', 'EXC_GUARD'}
    allowed_signals = {'SIGABRT', 'SIGSEGV', 'SIGBUS', 'SIGTRAP', 'SIGKILL'}
    allowed_namespaces = {'SIGNAL', 'FRONTBOARD', 'RUNNINGBOARD', 'DYLD', 'CODESIGNING'}
    result = {
        'exception_type': exception.get('type') if exception.get('type') in allowed_types else 'other',
        'signal': exception.get('signal') if exception.get('signal') in allowed_signals else 'other',
        'termination_namespace': termination.get('namespace') if termination.get('namespace') in allowed_namespaces else 'other',
    }
    if type(termination.get('code')) is int:
        result['termination_code'] = termination['code']
    # Module identities are static build inputs. Export only known system Swift
    # library basenames, never their path or the surrounding loader message.
    libraries = set()
    for value in termination.values():
        for line in value if isinstance(value, list) else [value]:
            if not isinstance(line, str) or not line.startswith('Library not loaded: '):
                continue
            name = line.split('\n', 1)[0].rsplit('/', 1)[-1].strip()
            if re.fullmatch(r'libswift[A-Za-z0-9_]+\.dylib|PersonalBrowser\.debug\.dylib', name):
                libraries.add(name)
    if libraries:
        result['missing_system_modules'] = sorted(libraries)
    # No filenames, paths, URLs, registers, messages, reasons, environment,
    # application-specific info or other runtime strings may leave this script.
    threads = report.get('threads', [])
    index = report.get('faultingThread', 0)
    frames = threads[index].get('frames', []) if type(index) is int and 0 <= index < len(threads) else []
    result['symbols'] = [f['symbol'] for f in frames[:48]
                         if isinstance(f.get('symbol'), str)
                         and len(f['symbol']) <= 220
                         and re.fullmatch(r'[A-Za-z_.$][A-Za-z0-9_.$ <>():,+\-\[\]~]*', f['symbol'])]
    return result


def read_report(path):
    text = path.read_text()
    decoder = json.JSONDecoder()
    first, end = decoder.raw_decode(text.lstrip())
    rest = text.lstrip()[end:].lstrip()
    return decoder.raw_decode(rest)[0] if rest else first


if __name__ == '__main__':
    reports = Path.home() / 'Library/Logs/DiagnosticReports'
    files = [p for p in reports.rglob('PersonalBrowser*.ips') if p.is_file()]
    summaries = []
    for path in sorted(files, key=lambda p: p.stat().st_mtime, reverse=True)[:6]:
        try:
            summaries.append(summarize(read_report(path)))
        except (ValueError, OSError, TypeError, KeyError):
            summaries.append({'unreadable': True})
    print(json.dumps({'reports': summaries}, indent=2))
