"""Select/create a real available simulator type, failing if the requested class is missing."""
import json
import os
import pathlib
import subprocess
import sys

PREFERENCES = {
    'compact': ['iPhone SE (3rd generation)', 'iPhone 13 mini', 'iPhone 16e', 'iPhone 17e'],
    'phone': ['iPhone 16', 'iPhone 17', 'iPhone 15'],
    'large': ['iPhone 16 Pro Max', 'iPhone 17 Pro Max', 'iPhone 15 Pro Max'],
    'tablet': ['iPad mini (A17 Pro)', 'iPad mini (6th generation)', 'iPad (A16)'],
    'tablet-landscape': ['iPad Pro 11-inch (M4)', 'iPad Pro 11-inch (M5)', 'iPad Air 11-inch (M3)'],
    'large-tablet': ['iPad Pro 13-inch (M4)', 'iPad Pro 13-inch (M5)', 'iPad Air 13-inch (M3)'],
}


def simctl(*args):
    return subprocess.check_output(['xcrun', 'simctl', *args], text=True).strip()


def select(profile):
    if profile not in PREFERENCES:
        raise SystemExit(f'Unknown device profile: {profile}')
    runtimes = json.loads(simctl('list', 'runtimes', '-j'))['runtimes']
    runtimes = [r for r in runtimes if r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
    runtimes.sort(key=lambda r: tuple(int(part) for part in r['version'].split('.')), reverse=True)
    if not runtimes:
        raise SystemExit('No available iOS simulator runtime')
    types = json.loads(simctl('list', 'devicetypes', '-j'))['devicetypes']
    by_name = {t['name']: t for t in types}
    # Creation validates runtime/hardware compatibility; try the requested alternatives, never another size class.
    failures = []
    for name in PREFERENCES[profile]:
        if name not in by_name:
            continue
        for runtime in runtimes:
            try:
                identifier = simctl('create', f'SpaceWorks-{profile}', by_name[name]['identifier'], runtime['identifier'])
            except subprocess.CalledProcessError:
                failures.append(f'{name} / {runtime["version"]}')
                continue
            simctl('boot', identifier)
            simctl('bootstatus', identifier, '-b')
            # UI tests also cover both appearances. This config exercises enlarged OS text on large devices.
            appearance = 'dark' if profile in ('large', 'tablet-landscape') else 'light'
            simctl('ui', identifier, 'appearance', appearance)
            if profile in ('large', 'tablet-landscape', 'large-tablet'):
                simctl('ui', identifier, 'content_size', 'accessibility-extra-extra-extra-large')
            evidence = {'profile': profile, 'name': name, 'udid': identifier, 'runtime': runtime['version'],
                        'appearance': appearance, 'landscape_required': profile == 'tablet-landscape',
                        'large_text': profile in ('large', 'tablet-landscape', 'large-tablet')}
            pathlib.Path('validation-device.json').write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
            with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output:
                output.write(f'SIMULATOR_ID={identifier}\nDEVICE_PROFILE={profile}\n')
            print(json.dumps(evidence))
            return
    raise SystemExit(f'No compatible requested simulator hardware for {profile}; attempted {failures}')


if __name__ == '__main__':
    select(sys.argv[1])
