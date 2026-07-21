declare namespace NodeJS {
  interface ProcessEnv {
    readonly GITHUB_REPO?: string;
    readonly GITHUB_TOKEN?: string;
  }
}

declare const process: {
  readonly env: NodeJS.ProcessEnv;
};
