import json
import unittest
from summarize_crashes import summarize


class CrashSummaryPrivacyTests(unittest.TestCase):
    def test_runtime_strings_and_paths_are_never_exported(self):
        report = {'exception': {'type': 'EXC_CRASH', 'signal': 'SIGABRT', 'reason': 'secret@example.com'},
                  'termination': {'namespace': 'SIGNAL', 'code': 6, 'indicator': 'https://private.example/',
                                  'reasons': ['Library not loaded: /usr/lib/swift/libswiftCoreAudioTypes.dylib',
                                              'Library not loaded: /private/secret@example.com']},
                  'procPath': '/private/user/path', 'asi': {'secret': 'sensitive'}, 'faultingThread': 0,
                  'threads': [{'frames': [{'symbol': 'AudioMixingController.init(defaults:)'},
                                         {'symbol': 'https://private.example/'}, {'symbol': '/private/path'},
                                         {'symbol': 'secret@example.com'}]}]}
        output = summarize(report)
        self.assertEqual(output['symbols'], ['AudioMixingController.init(defaults:)'])
        self.assertEqual(output['termination_code'], 6)
        self.assertEqual(output['missing_system_modules'], ['libswiftCoreAudioTypes.dylib'])
        text = json.dumps(output)
        for value in ['private', 'secret', 'sensitive', '@', 'https:']:
            self.assertNotIn(value, text)
