class BuildpackDependencyUpdater::Yarn < BuildpackDependencyUpdater
  def perform_dependency_specific_changes
    perform_default_versions_update
  end
end
