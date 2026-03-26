# Home-manager module evaluation adapter for nix-wrapper-modules.
#
# Evaluates arbitrary home-manager modules in a real HM context,
# extracts their side effects (packages, files, activation scripts,
# session variables), and produces a wrapper-module config with
# .wrap/.apply/.eval.
#
# home-manager is NOT a hard dependency of nix-wrapper-modules.
# The caller provides their own home-manager input.
{ lib, wlib }:
{
  /**
    Evaluate home-manager modules and produce a wrapper-module config.

    The returned value is a wrapper-module `.config` with the standard
    `.wrap`, `.apply`, `.eval`, and `.wrapper` interface, so consumers
    can further extend it.

    # Arguments

    - `pkgs`: The nixpkgs instance to use.
    - `home-manager`: The home-manager flake input (provides `lib.homeManagerConfiguration`).
    - `homeModules`: List of HM modules to evaluate (replaces old `homeModule`/`homeConfig`/`extraHomeModules`).
    - `mainPackage` (optional): The primary package to wrap. When omitted, auto-discovered
      from `hmConfig.programs.<name>.package` (first enabled program with a package attribute).
    - `programName` (optional): Hint for auto-discovery — name of the HM program to extract
      the package from (e.g., `"alacritty"`). Only used when `mainPackage` is null.
    - `extraSpecialArgs` (optional): Extra specialArgs to pass to `homeManagerConfiguration`. Default `{}`.
    - `stateVersion` (optional): HM state version for the evaluation context. Defaults to `"24.11"`.
    - `extractPackages` (optional): Extract `home.packages` → `extraPackages`. Default `true`.
    - `extractFiles` (optional): Extract `home.file` / `xdg.configFile` → derivation files. Default `true`.
    - `extractSessionVariables` (optional): Map `home.sessionVariables` → `env` with `mkDefault`. Default `true`.
    - `runActivation` (optional): Wire activation scripts into `runShell`. Default `false`.
      Activation scripts are always available in `passthru.hmAdapter.activationScripts`.

    # Example

    ```nix
    wlib.wrapHomeModule {
      inherit pkgs;
      home-manager = inputs.home-manager;
      homeModules = [
        inputs.nixkraken.homeManagerModules.nixkraken
        {
          programs.nixkraken = {
            enable = true;
            acceptEULA = true;
            user = { email = "user@example.com"; name = "user"; };
          };
          programs.git.userEmail = "user@example.com";
          programs.git.userName = "user";
        }
      ];
      mainPackage = inputs.nixkraken.packages.''${pkgs.system}.gitkraken;
    }
    ```

    # Limitations

    - When `runActivation = true`, activation scripts run on every launch (not just once).
      This is correct for idempotent scripts but may be undesirable for others.
    - Setting `XDG_CONFIG_HOME` (when xdg config files are extracted) redirects ALL
      XDG config lookups to the wrapper derivation. Use `.wrap` to override if needed.
    - Activation scripts referencing `$newGenPath` or `$oldGenPath` will find them empty.
  */
  wrapHomeModule =
    {
      pkgs,
      home-manager,
      homeModules,
      mainPackage ? null,
      programName ? null,
      extraSpecialArgs ? { },
      stateVersion ? "24.11",
      extractPackages ? true,
      extractFiles ? true,
      extractSessionVariables ? true,
      runActivation ? false,
    }:
    let
      # ── Step 1: Evaluate the HM modules in a real HM context ─────────

      hmEval = home-manager.lib.homeManagerConfiguration {
        inherit pkgs extraSpecialArgs;
        modules = homeModules ++ [
          {
            home.username = "wrapper-user";
            home.homeDirectory = "/homeless-shelter";
            home.stateVersion = stateVersion;
          }
        ];
      };

      hmConfig = hmEval.config;

      # ── Step 1b: Auto-discover mainPackage if not provided ─────────
      #
      # Search hmConfig.programs.* for enabled programs with a package
      # attribute. If programName is given, use that directly. Otherwise
      # find the first enabled program.

      discoverMainPackage =
        let
          programs = hmConfig.programs or { };

          # 1. Try programs.<programName>.package directly
          fromProgramsHint =
            if programName != null && programs ? ${programName} then
              programs.${programName}.package or null
            else
              null;

          # 2. Match home.packages by pname, meta.mainProgram, or name prefix
          fromHomePackages =
            let
              allPkgs = hmConfig.home.packages or [ ];
              baselinePkgs = map toString (baselineEval.config.home.packages or [ ]);
              # Only consider packages added by user modules (not HM baseline)
              userPkgs = builtins.filter (p: !(builtins.elem (toString p) baselinePkgs)) allPkgs;
              matchesHint =
                p:
                programName != null
                && (
                  (p.pname or "") == programName
                  || (p.meta.mainProgram or "") == programName
                  || lib.hasPrefix programName (p.name or "")
                );
              hinted = if programName != null then builtins.filter matchesHint userPkgs else [ ];
            in
            if hinted != [ ] then
              builtins.head hinted
            else if builtins.length userPkgs == 1 then
              # If there's exactly one user-added package, it's almost certainly the main one
              builtins.head userPkgs
            else
              null;

          # 3. Scan programs.* for the first enabled program with a package (tryEval for safety)
          firstEnabledPackage =
            let
              names = lib.attrNames programs;
              tryGetPackage =
                name:
                let
                  result = builtins.tryEval (
                    let
                      p = programs.${name};
                    in
                    if (p.enable or false) && (p ? package) then p.package else null
                  );
                in
                if result.success then result.value else null;
              packages = builtins.filter (p: p != null) (map tryGetPackage names);
            in
            if packages != [ ] then builtins.head packages else null;
        in
        if fromProgramsHint != null then
          fromProgramsHint
        else if fromHomePackages != null then
          fromHomePackages
        else
          firstEnabledPackage;

      resolvedMainPackage =
        if mainPackage != null then
          mainPackage
        else
          let
            discovered = discoverMainPackage;
          in
          if discovered != null then
            discovered
          else
            throw "wrapHomeModule: mainPackage not provided and could not be auto-discovered from hmConfig.programs.*. Provide mainPackage explicitly or set programName to hint which program to use.";

      # ── Step 2: Baseline evaluation for diff filtering ───────────────
      #
      # Evaluate HM with an empty module to discover HM-internal entries.
      # We filter these out rather than maintaining a manual blocklist.

      baselineEval = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          {
            home.username = "wrapper-user";
            home.homeDirectory = "/homeless-shelter";
            home.stateVersion = stateVersion;
          }
        ];
      };
      baselineFileNames = lib.attrNames baselineEval.config.home.file;
      baselineXdgNames = lib.attrNames baselineEval.config.xdg.configFile;
      baselineActivationNames = lib.attrNames (baselineEval.config.home.activation or { });

      # ── Step 3: Extract packages ────────────────────────────────────

      extractedExtraPackages = if !extractPackages then [ ] else hmConfig.home.packages or [ ];

      # ── Step 4: Extract session variables ───────────────────────────

      sessionVars =
        if extractSessionVariables then
          lib.filterAttrs (name: _: name != "XDG_CONFIG_HOME") (hmConfig.home.sessionVariables or { })
        else
          { };

      # ── Step 5: Extract and linearize activation scripts ────────────

      userActivation = lib.filterAttrs (name: _: !(builtins.elem name baselineActivationNames)) (
        hmConfig.home.activation or { }
      );

      activationList = lib.mapAttrsToList (name: v: { inherit name; } // v) userActivation;

      sortedActivation =
        if activationList == [ ] then
          [ ]
        else
          let
            sorted = lib.toposort (
              a: b:
              builtins.elem (a.name or "") (b.after or [ ]) || builtins.elem (b.name or "") (a.before or [ ])
            ) activationList;
          in
          if sorted ? result then
            sorted.result
          else
            throw "wrapHomeModule: cycle detected in home.activation DAG";

      activationScript = lib.concatMapStringsSep "\n" (entry: entry.data or "") sortedActivation;

      # ── Step 6: Extract files ───────────────────────────────────────
      #
      # In HM, xdg.configFile entries are merged into home.file with an
      # absolute-path target prefixed by xdg.configHome.  We read
      # xdg.configFile separately (targets relative to XDG_CONFIG_HOME)
      # and filter those entries out of home.file to avoid duplication.
      #
      # Baseline diff handles HM-internal files, but user xdg entries
      # still get merged into home.file by HM, so we dedup those too.
      #
      # For text-based entries we use constructFiles (embeds content directly
      # in the derivation via passAsFile — no dependency tracking issues).
      # For source-only entries we copy via buildCommand and add sources as
      # explicit drv attributes to ensure they're tracked as dependencies.

      getEnabledFiles = files: lib.filterAttrs (_: f: f.enable or true) (files);

      hmXdgConfigFiles =
        if extractFiles then
          lib.filterAttrs (name: _: !(builtins.elem name baselineXdgNames)) (
            getEnabledFiles hmConfig.xdg.configFile
          )
        else
          { };

      hmAllHomeFiles =
        if extractFiles then
          lib.filterAttrs (name: _: !(builtins.elem name baselineFileNames)) (
            getEnabledFiles hmConfig.home.file
          )
        else
          { };

      # Filter out user xdg entries that were merged into home.file.
      # HM merges xdg.configFile entries into home.file under the attribute
      # name "${xdg.configHome}/${name}".  We filter by computed attr name
      # rather than target path for reliability.
      xdgConfigHome = hmConfig.xdg.configHome;
      xdgMergedAttrNames = map (name: "${xdgConfigHome}/${name}") (lib.attrNames hmXdgConfigFiles);
      hmHomeFiles = lib.filterAttrs (name: _: !(builtins.elem name xdgMergedAttrNames)) hmAllHomeFiles;

      # Normalise home.file targets (may be absolute due to homeDirectory stub)
      homeDir = hmConfig.home.homeDirectory;
      normalizeTarget =
        target:
        if lib.hasPrefix "${homeDir}/" target then lib.removePrefix "${homeDir}/" target else target;

      # Normalise xdg.configFile targets — strip configHome-related prefixes
      # so files are stored relative to XDG_CONFIG_HOME in the derivation.
      # HM target paths may be absolute (/homeless-shelter/.config/foo),
      # relative to HOME (.config/foo), or already bare (foo).
      normalizeXdgTarget =
        target:
        if lib.hasPrefix "${xdgConfigHome}/" target then
          lib.removePrefix "${xdgConfigHome}/" target
        else if lib.hasPrefix "${homeDir}/.config/" target then
          lib.removePrefix "${homeDir}/.config/" target
        else if lib.hasPrefix ".config/" target then
          lib.removePrefix ".config/" target
        else
          target;

      # Sanitise attribute names for use as constructFiles keys and drv attributes.
      # Must be valid as both Nix attribute names and bash variable names
      # (passAsFile turns them into $keyPath variables).
      sanitizeName =
        name:
        let
          raw =
            builtins.replaceStrings
              [
                "/"
                "."
                "-"
                " "
                "~"
                "+"
                "@"
              ]
              [
                "_"
                "_"
                "_"
                "_"
                "_"
                "_"
                "_"
              ]
              name;
        in
        # Ensure it starts with a letter or underscore (valid bash var)
        if builtins.match "[a-zA-Z_].*" raw != null then raw else "_${raw}";

      # Separate text entries (→ constructFiles) from source-only entries (→ buildCommand copy)
      hasText = f: f.text or null != null;
      textHomeFiles = lib.filterAttrs (_: hasText) hmHomeFiles;
      sourceHomeFiles = lib.filterAttrs (_: f: !hasText f) hmHomeFiles;
      textXdgFiles = lib.filterAttrs (_: hasText) hmXdgConfigFiles;
      sourceXdgFiles = lib.filterAttrs (_: f: !hasText f) hmXdgConfigFiles;

      # constructFiles entries embed text directly — no source path dependency needed
      mkConstructEntry =
        prefix: normalizeFn: name: fileCfg:
        let
          target = normalizeFn (fileCfg.target or name);
        in
        {
          name = "hm_${sanitizeName name}";
          value = {
            relPath = "${prefix}${target}";
            content = fileCfg.text;
          };
        };

      constructFileEntries =
        lib.mapAttrs' (mkConstructEntry "hm-home/" normalizeTarget) textHomeFiles
        // lib.mapAttrs' (mkConstructEntry "hm-xdg-config/" normalizeXdgTarget) textXdgFiles;

      # For source-only entries, collect sources and build copy commands.
      # Sources are added as explicit drv attributes to guarantee dependency tracking.
      sourceEntries =
        let
          mkEntry =
            prefix: normalizeFn: name: fileCfg:
            let
              target = prefix + (normalizeFn (fileCfg.target or name));
              attrName = "hmSrc_${sanitizeName name}";
            in
            {
              inherit attrName target;
              source = fileCfg.source;
              executable = fileCfg.executable == true;
            };
        in
        lib.mapAttrsToList (mkEntry "hm-home/" normalizeTarget) sourceHomeFiles
        ++ lib.mapAttrsToList (mkEntry "hm-xdg-config/" normalizeXdgTarget) sourceXdgFiles;

      sourceCopyScript = lib.concatMapStringsSep "\n" (entry: ''
        mkdir -p "$(dirname "${placeholder "out"}/${entry.target}")"
        cp -rL "''${${entry.attrName}}" "${placeholder "out"}/${entry.target}"
        ${lib.optionalString entry.executable ''
          chmod +x "${placeholder "out"}/${entry.target}"
        ''}
      '') sourceEntries;

      # Drv attributes that reference the source paths (ensures dependency tracking)
      sourceDrvAttrs = lib.listToAttrs (
        map (entry: {
          name = entry.attrName;
          value = entry.source;
        }) sourceEntries
      );

      hasConstructFiles = constructFileEntries != { };
      hasSourceFiles = sourceEntries != [ ];
      hasXdgFiles = hmXdgConfigFiles != { };
      hasActivation = activationScript != "";

      # ── Step 7: Produce a wrapper-module config ─────────────────────
    in
    (wlib.evalModules {
      modules = [
        wlib.modules.default
        { inherit pkgs; }
        (
          { config, lib, ... }:
          {
            package = resolvedMainPackage;

            extraPackages = lib.mkIf (extractedExtraPackages != [ ]) extractedExtraPackages;

            constructFiles = lib.mkIf hasConstructFiles constructFileEntries;

            # Source-only files: copy from store paths via buildCommand.
            # The source derivations are added as drv attributes below
            # to guarantee Nix tracks them as build dependencies.
            buildCommand.hmSourceFiles = lib.mkIf hasSourceFiles {
              before = [
                "makeWrapper"
                "symlinkScript"
              ];
              data = sourceCopyScript;
            };

            drv = lib.mkIf hasSourceFiles sourceDrvAttrs;

            runShell = lib.mkIf (runActivation && hasActivation) [
              {
                name = "hmActivation";
                data = ''
                  # Stub HM activation variables that don't apply in wrapper context
                  DRY_RUN_CMD=""
                  VERBOSE_ARG=""
                  newGenPath=""
                  oldGenPath=""
                  ${activationScript}
                '';
              }
            ];

            # Map session variables and XDG_CONFIG_HOME to env.
            # Both use mkDefault so consumers can override via .wrap or .apply.
            env = lib.mkMerge [
              (lib.mkIf (sessionVars != { }) (lib.mapAttrs (_: v: lib.mkDefault (toString v)) sessionVars))
              (lib.mkIf hasXdgFiles { XDG_CONFIG_HOME = lib.mkDefault "${placeholder "out"}/hm-xdg-config"; })
            ];

            # Expose extracted data as passthru for user inspection and customization.
            passthru.hmAdapter = {
              inherit hmConfig extractedExtraPackages;
              sessionVariables = sessionVars;
              homeFiles = hmHomeFiles;
              xdgConfigFiles = hmXdgConfigFiles;
              activationScripts = userActivation;
              systemdUserServices = hmConfig.systemd.user.services or { };
              xdgConfigPath = "${config.wrapper}/hm-xdg-config";
              homePath = "${config.wrapper}/hm-home";
            };
          }
        )
      ];
    }).config;

  /**
    Generate bind mount mappings from an hmAdapter passthru.

    Takes the `passthru.hmAdapter` attribute set and returns an attrset
    mapping store paths to their intended relative target paths, suitable
    for use with bind-mount or symlink mechanisms.

    # Example

    ```nix
    let
      cfg = wlib.wrapHomeModule { ... };
      binds = wlib.mkBinds cfg.passthru.hmAdapter;
    in
    # binds looks like:
    # { "!out!.../hm-xdg-config/foo" = ".config/foo"; ... }
    ```

    Uses `placeholder "out"` for source paths instead of resolved store paths.
    This avoids string context being stripped when used as attrset keys in
    `bwrapConfig.binds.ro`, which goes through `types.attrsOf types.str`.
    The placeholders are substituted with the real store path at build time.
  */
  mkBinds =
    hmAdapter:
    let
      out = builtins.placeholder "out";
    in
    lib.listToAttrs (
      lib.mapAttrsToList (name: _: {
        name = "${out}/hm-xdg-config/${name}";
        value = ".config/${name}";
      }) hmAdapter.xdgConfigFiles
      ++ lib.mapAttrsToList (name: fileCfg: {
        name = "${out}/hm-home/${fileCfg.target or name}";
        value = fileCfg.target or name;
      }) hmAdapter.homeFiles
    );
}
