# encoding: utf-8
require 'spec_helper'
require_relative '../../lib/update-dependency-in-buildpack-job'

describe UpdateDependencyInBuildpackJob do
  let(:buildpacks_ci_dir) { Dir.mktmpdir }
  let(:binary_built_out_dir) { Dir.mktmpdir }
  let(:version)                      { 'override' }
  let(:dependency)                   { 'override' }
  let(:removed_versions)             { %w(override) }
  let(:buildpack_dependency_updater) { double(:buildpack_dependency_updater, dependency_version: version,
                                                                             removed_versions: removed_versions,
                                                                             run!: nil) }

  subject { described_class.new(buildpacks_ci_dir, binary_built_out_dir) }

  before do
    @old_dependency = ENV.fetch('DEPENDENCY', nil)
    @old_buildpack_name = ENV.fetch('BUILDPACK_NAME', nil)
    @old_tracker_api_token = ENV.fetch('TRACKER_API_TOKEN', nil)
    @old_tracker_project_id = ENV.fetch('TRACKER_PROJECT_ID', nil)
    @old_tracker_requester_id = ENV.fetch('TRACKER_REQUESTER_ID', nil)

    ENV.store('DEPENDENCY', dependency)
    ENV.store('BUILDPACK_NAME', 'does not matter')
    ENV.store('TRACKER_API_TOKEN', 'does not matter')
    ENV.store('TRACKER_PROJECT_ID', 'does not matter')
    ENV.store('TRACKER_REQUESTER_ID', 'does not matter')

    allow(BuildpackDependencyUpdater).to receive(:create).and_return(buildpack_dependency_updater)
  end

  after do
    ENV.store('DEPENDENCY', @old_dependency)
    ENV.store('BUILDPACK_NAME', @old_buildpack_name)
    ENV.store('TRACKER_API_TOKEN', @old_tracker_api_token)
    ENV.store('TRACKER_PROJECT_ID', @old_tracker_project_id)
    ENV.store('TRACKER_REQUESTER_ID', @old_tracker_requester_id)

    FileUtils.rm_rf(buildpacks_ci_dir)
    FileUtils.rm_rf(binary_built_out_dir)
  end

  describe '#update_buildpack' do
    let(:dependency)                   { 'nginx' }
    let(:buildpack_dir)                { Dir.mktmpdir }
    let(:version)                      { '1.11.3' }
    let(:removed_versions)             { %w(1.11.1) }

    after { FileUtils.rm_rf(buildpack_dir) }

    it 'runs the BuildpackDependencyUpdater' do
      expect(buildpack_dependency_updater).to receive(:run!)
      subject.update_buildpack
    end

    it 'outputs that the manifest is being updated' do
      expect { subject.update_buildpack }.to output("Updating manifest with nginx 1.11.3...\n").to_stdout
    end

    it 'returns the buildpack directory, dependency, version, and removed versions' do
      expected_buildpack_dir = File.expand_path(File.join(buildpacks_ci_dir, '..', "buildpack"))
      expect(subject.update_buildpack).to eq([expected_buildpack_dir, 'nginx', '1.11.3', ['1.11.1']])
    end
  end

  describe '#extract_source_info' do
    context "with a commit containing sha or md5 verification" do
      let(:git_commit_message) {<<~COMMIT
        Build node - 4.4.7

        ---
        filename: binary-builder/node-4.4.7-linux-x64.tgz
        version: 4.4.7
        md5: d311066e117d2c3f94d6c795dbde6cac
        sha256: 4385394899eabdebc12d353aebe3af2364056e9f8623d6a95f31f75c111bcbc0
        source url: https://nodejs.org/dist/v4.4.7/node-v4.4.7.tar.gz
        source sha256: cbe1c6e421969dd5639d0fbaa6d3c1f56c0463b87efe75be8594638da4d8fc4f
      COMMIT
      }

      it "returns the source info including the source url and source sha or md5" do
        expected_source_info = {
                                'source url' => 'https://nodejs.org/dist/v4.4.7/node-v4.4.7.tar.gz',
                                'source sha256' => 'cbe1c6e421969dd5639d0fbaa6d3c1f56c0463b87efe75be8594638da4d8fc4f'
                                }
        extracted_source_info = subject.extract_source_info(git_commit_message)
        expect(extracted_source_info).to eq(expected_source_info)
      end
    end

    context "with a commit containing gpg verification" do
      let(:git_commit_message) {<<~COMMIT
        Build nginx - 1.11.3

        ---
        filename: binary-builder/nginx-1.11.3-linux-x64.tgz
        version: 1.11.3
        md5: 4944b39c77b4fc245df45e60eae635b3
        sha256: a35fd46bf45c6dec8f0e01c59e15da71f485b86f5a18269db7d1f3861ef0af16
        source url: http://nginx.org/download/nginx-1.11.3.tar.gz
        source gpg-signature: |-
          -----BEGIN PGP SIGNATURE-----
          Version: GnuPG v2

          iQEcBAABCAAGBQJXl2zVAAoJEFIKmZOhwFL4L30IAMXQIwLWJU+rd8IGeclGDzzL
          FU0nD/LJs8mzMD+m+IjO4/tk3ADzkZHtjEWyb1tzi2GazhqsEnmoYfbthGT+jWDO
          xj/JhNBpllEKFeUXN8BiJ3NXoBtPzPEM7OOK5xIeZ1DQC2Ob/LwpiN9UwZUf6Jsn
          rpgSkiz2ZnSxxzH329rJSZCXI3RhGabBG0voN54z8ugWslvEm7Ud6fhQRQxh5xFi
          6Z22xTo184GUQktG5BSeDp1tKqww9P+os7m7FuhNnKl7ADDnAnI1s59tvUf1icCC
          ZpCRCONaXnWxlmrimA/6nJGIp6zARe6IDClb8PWloxef2SR72bQXH4Q9uUPoZMc=
          =kC5f
          -----END PGP SIGNATURE-----
      COMMIT
      }

      it "returns the source info including the source url and source's gpg signature" do
        gpg_signature = <<~SOURCE_INFO
        -----BEGIN PGP SIGNATURE-----
        Version: GnuPG v2

        iQEcBAABCAAGBQJXl2zVAAoJEFIKmZOhwFL4L30IAMXQIwLWJU+rd8IGeclGDzzL
        FU0nD/LJs8mzMD+m+IjO4/tk3ADzkZHtjEWyb1tzi2GazhqsEnmoYfbthGT+jWDO
        xj/JhNBpllEKFeUXN8BiJ3NXoBtPzPEM7OOK5xIeZ1DQC2Ob/LwpiN9UwZUf6Jsn
        rpgSkiz2ZnSxxzH329rJSZCXI3RhGabBG0voN54z8ugWslvEm7Ud6fhQRQxh5xFi
        6Z22xTo184GUQktG5BSeDp1tKqww9P+os7m7FuhNnKl7ADDnAnI1s59tvUf1icCC
        ZpCRCONaXnWxlmrimA/6nJGIp6zARe6IDClb8PWloxef2SR72bQXH4Q9uUPoZMc=
        =kC5f
        -----END PGP SIGNATURE-----
        SOURCE_INFO

        expected_source_info = {
                                 'source url' => 'http://nginx.org/download/nginx-1.11.3.tar.gz',
                                 'source gpg-signature' => gpg_signature.strip
                               }

        extracted_source_info = subject.extract_source_info(git_commit_message)
        expect(extracted_source_info).to eq(expected_source_info)
      end
    end
  end

  describe '#write_git_commit' do
    let(:git_commit_message) { double(:git_commit_message) }
    let(:source_info)        { { 'source a': 1, 'source b': 2 } }
    let(:buildpack_dir)      { Dir.mktmpdir }
    let(:dependency)         { 'node' }
    let(:story_ids)          { [123456] }
    let(:version)            { '4.4.7' }
    let(:removed_versions)   { ['4.4.4', '4.4.5'] }

    before do
      allow(GitClient).to receive(:last_commit_message).with(binary_built_out_dir, 0, 'binary-built-output/node-built.yml').and_return(git_commit_message)
      allow(subject).to receive(:extract_source_info).with(git_commit_message).and_return(source_info)
    end

    after { FileUtils.rm_rf(buildpack_dir) }

    it "git adds everything and makes a git commit" do
      expect(GitClient).to receive(:add_everything)
      expect(GitClient).to receive(:safe_commit).with("Add node 4.4.7, remove node 4.4.4, 4.4.5\n\nsource a: 1\nsource b: 2\n\n[#123456]")
      subject.write_git_commit(buildpack_dir, dependency, story_ids, version, removed_versions)
    end
  end

  describe '#run!' do
    let(:tracker_client)   { double(:tracker_client) }
    let(:dependency)       { 'node' }
    let(:story_ids)        { [123456] }
    let(:buildpack_dir)    { Dir.mktmpdir }
    let(:manifest_yml)     { TempFile.new('manifest.yml', buildpack_dir) }
    let(:removed_versions) { %w(4.4.5) }
    let(:manifest_content) { <<~MANIFEST
---
dependencies:
  - name: node
    version: 4.4.5
MANIFEST
          }

    before do
      allow(TrackerClient).to receive(:new).and_return(tracker_client)
      allow(tracker_client).to receive(:find_unaccepted_story_ids).with("include new node 4.4.7").and_return([123456])
      File.write(manifest_yml, manifest_content)
    end

    after { FileUtils.rm_rf(buildpack_dir) }

    context 'the new version of the dependency is lower than the version currently in the manifest' do
      let(:version)          { '4.4.4' }

      it 'does not update the buildpack or make a git commit' do
        expect(subject).not_to receive(:update_buildpack).and_return([buildpack_dir, dependency, version, removed_versions])
        expect(subject).not_to receive(:write_git_commit)
        subject.run!
      end

    end

    context 'the new version of the dependency is greater than or equal to the version currently in the manifest' do
      let(:version)          { '4.4.7' }

      it 'updates the buildpack and makes a git commit with the matching unaccepted story ids' do
        expect(subject).to receive(:update_buildpack).and_return([buildpack_dir, dependency, version, removed_versions])
        expect(subject).to receive(:write_git_commit).with(buildpack_dir, 'node', [123456], '4.4.7', ['4.4.5'])
        subject.run!
      end
    end
  end
end
