export type PrimaryUseCase =
  | "GeneralChat"
  | "Reasoning"
  | "Coding"
  | "DeepResearch"
  | "All";

export type AllocationMode = "Comfortable" | "Aggressive";
export type ProvenancePreferenceMode = "None" | "Prefer" | "Avoid" | "Require";
export type ModelVendor =
  | "Alibaba" | "Cohere" | "DeepSeek" | "Google" | "IBM"
  | "Meta" | "Microsoft" | "MistralAI";
export type ModelCountry = "Canada" | "China" | "France" | "UnitedStates";
export type OllamaBackend = "CUDA" | "ROCm" | "Vulkan" | "DirectML" | "CPU";

export interface OllamaModelCatalogEntry {
  id: string;
  displayOrder: number;
  displayName: string;
  family: string;
  variant: string;
  parameterCountBillions: number;
  quantization: string;
  organization: ModelVendor;
  country: ModelCountry;
  tasks: Array<"GeneralChat" | "Reasoning" | "Coding" | "DocumentQa">;
  qualityScore: number;
  ollamaTag: string;
  downloadGiB: number;
  modelGiB: number;
  kvCacheGiB: number;
  contextTokens: number;
  minRamGiB: number;
  minVramGiB: number;
  backend: OllamaBackend;
  sourceUrl: string;
  license: string;
  provenanceConfidence: "high" | "medium" | "low";
}

export interface OllamaModelCatalog {
  schemaVersion: 2;
  catalogVersion: string;
  publishedAt: string;
  runtime: "Ollama";
  notes: string;
  models: OllamaModelCatalogEntry[];
}
