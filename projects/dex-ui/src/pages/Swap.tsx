import React from "react";
import { size } from "src/breakpoints";
import { LoadingTemplate } from "src/components/LoadingTemplate";
import { Page } from "src/components/Page";
import { Title } from "src/components/PageComponents/Title";
import { SwapRoot } from "src/components/Swap/SwapRoot";
import { useWellTokens } from "src/tokens/useWellTokens";
import styled from "styled-components";

export const Swap = () => {
  const { isLoading, data } = useWellTokens();

  const loading = !data || isLoading || !data.length;

  return (
    <Page>
      <Title title="Swap" fontWeight={"600"} largeOnMobile />
      {loading ? (
        <Container>
          <LoadingTemplate.Input />
          <LoadingTemplate.Arrow />
          <LoadingTemplate.Input />
          <LoadingTemplate.LabelValue labelWidth={120} />
          <LoadingTemplate.Button />
        </Container>
      ) : (
        <SwapRoot />
      )}
    </Page>
  );
};

const Container = styled.div`
  width: 384px;
  display: flex;
  flex-direction: column;
  gap: 24px;
  @media (max-width: ${size.mobile}) {
    width: 100%;
    gap: 16px;
  }
`;
