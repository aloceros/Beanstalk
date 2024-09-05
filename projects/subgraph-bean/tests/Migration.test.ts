import { clearStore, afterEach, describe, test, assert } from "matchstick-as/assembly/index";
import { handleInitBeanEntity } from "../src/utils/b3-migration/BeanInit";
import { mockBlock } from "../../subgraph-core/tests/event-mocking/Block";
import { BEAN_ERC20 } from "../../subgraph-core/utils/Constants";
import { BEAN_INITIAL_VALUES } from "../cache-builder/results/BeanInit_arb";

describe("Beanstalk 3 Migration", () => {
  afterEach(() => {
    clearStore();
  });

  test("Bean entity initialization", () => {
    handleInitBeanEntity(mockBlock());
    assert.fieldEquals("Bean", BEAN_ERC20.toHexString(), "volume", BEAN_INITIAL_VALUES.volume.toString());
    assert.fieldEquals("Bean", BEAN_ERC20.toHexString(), "crosses", BEAN_INITIAL_VALUES.crosses.toString());
    assert.fieldEquals(
      "BeanHourlySnapshot",
      BEAN_ERC20.toHexString() + "-" + BEAN_INITIAL_VALUES.lastSeason.toString(),
      "crosses",
      BEAN_INITIAL_VALUES.crosses.toString()
    );
  });
});
