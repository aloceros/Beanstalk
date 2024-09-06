import { DexSettings } from ".";

export const DevSettings: DexSettings = {
  PRODUCTION: false,
  SUBGRAPH_URL: "https://graph.node.bean.money/subgraphs/name/basin",
  // SUBGRAPH_URL: "http://127.0.0.1:8000/subgraphs/name/beanstalk-wells",
  BEANSTALK_SUBGRAPH_URL: "https://graph.node.bean.money/subgraphs/name/beanstalk",
  WELLS_ORIGIN_BLOCK: parseInt(import.meta.env.VITE_WELLS_ORIGIN_BLOCK) || 17977922,
  LOAD_HISTORY_FROM_GRAPH: !!parseInt(import.meta.env.VITE_LOAD_HISTORY_FROM_GRAPH) || false
};
