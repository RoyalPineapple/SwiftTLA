require 'yaml'
require 'open3'

root = File.expand_path('../../..', __dir__)
workflow = YAML.load_file(File.join(root, '.github/workflows/ci.yml'))
script = File.join(root, 'scripts/proof-family-inputs.sh')

expected = {
  'scoped-action-binding' => ['Verification/Semantics/scoped-action-binding.batch', 'LexicalBindingTests'],
  'boolean-expression' => ['Verification/Semantics/boolean-expression.batch', 'ShortCircuitFailureProofTests|BooleanBranchLoweringContractTests']
}
expected.each do |family, (batch, tests)|
  output, error, result = Open3.capture3('bash', script, family)
  raise error unless result.success?
  raise "wrong inputs for #{family}" unless output == "batch=#{batch}\ntests=#{tests}\n"
end
['none', '', '../action-composition', 'boolean-expression;exit 0'].each do |family|
  output, error, result = Open3.capture3('bash', script, family)
  raise 'invalid family accepted' unless result.exitstatus == 64 && output.empty? && error.include?('unknown proof family')
end

# These expressions are the Actions scheduling boundary, not shell commands.
admission = "${{ github.event_name != 'workflow_dispatch' || !inputs.proof_family || inputs.proof_family == 'none' }}"
%w[swift-test-suites semantic-proof-diagnostic apple-platform-examples canonical-corpus-export].each do |job|
  raise "family dispatch can run admission job #{job}" unless workflow.fetch('jobs').fetch(job).fetch('if') == admission
end
raise 'aggregate can report family diagnostics as admission' unless workflow['jobs']['swift-tests']['if'] ==
  "${{ always() && (github.event_name != 'workflow_dispatch' || !inputs.proof_family || inputs.proof_family == 'none') }}"
raise 'family checks can cancel admission' unless workflow['concurrency']['cancel-in-progress'] == admission
raise 'family concurrency is not isolated' unless workflow['concurrency']['group'].include?('github.run_id') &&
  workflow['concurrency']['group'].include?("{0}-family-{1}-{2}-{3}")
raise 'family diagnostics can run on PR events' unless workflow['jobs']['proof-family']['if'] ==
  "${{ github.event_name == 'workflow_dispatch' && inputs.proof_family != '' && inputs.proof_family != 'none' }}"
puts 'Family allowlist and admission-isolation contracts passed.'
