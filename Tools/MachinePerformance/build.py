"""Stage a small release client using the exact production sources and the guarded port builder."""
import argparse
from pathlib import Path
import fcntl
import hashlib
import json
import os
import shutil
import subprocess

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--wrapper', required=True, type=Path, help='local-validation.sh supporting port-build 4 release')
    parser.add_argument('--repo', type=Path, help='production checkout to measure')
    parser.add_argument('--heap-probe', action='store_true', help='also build optional Darwin allocation probe')
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    repo = args.repo.resolve() if args.repo else Path(subprocess.check_output(['git','rev-parse','--show-toplevel'], cwd=here, text=True).strip())
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    pkg = repo/'.context'/'machine-performance-build'
    pkg.mkdir(parents=True, exist_ok=True)
    stage_lock = (pkg/'stage.lock').open('a')
    fcntl.flock(stage_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    if (out/'build.json').exists():
        parser.error("use a fresh build output directory")
    def copy(source, dest):
        dest.parent.mkdir(parents=True, exist_ok=True)
        if not dest.exists() or source.read_bytes() != dest.read_bytes():
            shutil.copy2(source, dest)
    manifest = (repo/'Package.swift').read_text()
    marker = '        // Canonical compiler models'
    assert manifest.count(marker)==1
    (pkg/'Package.swift').write_text(manifest.split(marker)[0]+'''        .target(name: "BenchModels", dependencies: ["SwiftTLA", "SwiftTLAMacros"], swiftSettings: settings),
        .executableTarget(name: "tlc-validate", dependencies: ["SwiftTLA", "BenchModels"], path: "Sources/Client")
    ]
)
''')
    if args.heap_probe:
        probe = pkg/'HeapProbePackage'
        (probe/'Sources/HeapProbe/include').mkdir(parents=True,exist_ok=True)
        (probe/'Package.swift').write_text('// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: "HeapProbePackage", products: [.library(name:"HeapProbe",type:.dynamic,targets:["HeapProbe"])],targets:[.target(name:"HeapProbe")])\n')
        (probe/'Sources/HeapProbe/include/HeapProbe.h').write_text('void bench_begin(void);\n')
        copy(here/'HeapProbe.c', probe/'Sources/HeapProbe/probe.c')
        mf=pkg/'Package.swift'
        mf.write_text(mf.read_text().replace('        .package(url:', '        .package(path: "HeapProbePackage"),\n        .package(url:', 1)
            .replace('["SwiftTLA", "BenchModels"]', '["SwiftTLA", "BenchModels", .product(name:"HeapProbe",package:"HeapProbePackage")]'))
    copy(repo/'Package.resolved', pkg/'Package.resolved')
    sources = {}
    (pkg/'Sources').mkdir(exist_ok=True)
    for name in ['SwiftTLA','SwiftTLAMacros','SwiftTLACompilerSupport','SwiftTLAPlugin']:
        dest = pkg/'Sources'/name
        source = repo/'Sources'/name
        if not dest.exists(): dest.symlink_to(source, target_is_directory=True)
        assert dest.resolve()==source.resolve()
        for file in source.rglob('*.swift'): sources[str(file.relative_to(repo))]=sha(file)
    # SwiftPM can reuse expansions after a symlinked macro changes. Bind its bytes to the wrapper cache key.
    production_digest = hashlib.sha256(json.dumps(sources, sort_keys=True).encode()).hexdigest()
    with (pkg/'Package.swift').open('a') as manifest_file:
        manifest_file.write('// Production inputs ' + production_digest + '\n')
    for src, target in [(here/'Models.swift','BenchModels/Models.swift'),(here/'Client.swift','Client/main.swift'),
                        *((repo/f'Sources/UpstreamParity/Examples/{item}.swift',f'BenchModels/{item}.swift')
                          for item in ['BoundedFIFO','CoffeeCan','NanoBlockchain']),
                        (repo/'Sources/UpstreamParity/ValidationModels/ConfiguredCounter.swift','BenchModels/ConfiguredCounter.swift')]:
        copy(src,pkg/'Sources'/target)
        sources[str(src.relative_to(repo)) if src.is_relative_to(repo) else str(src)] = sha(src)
    wrapper=args.wrapper.resolve()
    with (out/'build.log').open('wb') as log:
        run=subprocess.run([wrapper,'port-build','4','release'],cwd=pkg,stderr=log,stdout=subprocess.PIPE,check=True)
    for path, digest in sources.items():
        if sha(repo/path) != digest:
            raise RuntimeError(f"source changed during build: {path}")
    binary=Path(run.stdout.decode().strip().splitlines()[-1])
    shutil.copy2(binary,out/'machine-performance')
    if args.heap_probe:
        shutil.copy2(binary.parent/'libHeapProbe.dylib',out/'libHeapProbe.dylib')
        sources["HeapProbe.c"]=sha(here/'HeapProbe.c')
    receipt={'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),
             'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
             'developerDir':os.environ.get('DEVELOPER_DIR'), 'machine':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),
             'releaseSHA256':sha(out/'machine-performance'),'inputs':sources, 'manifestSHA256':sha(pkg/'Package.swift'), 'packageResolvedSHA256':sha(pkg/'Package.resolved'),'wrapper':str(wrapper),'wrapperSHA256':sha(wrapper)}
    (out/'build.json').write_text(json.dumps(receipt,indent=2))
if __name__=='__main__': main()
