import React from "react";
import styled from "styled-components";
import { FormProvider, useForm, useFormContext, useWatch } from "react-hook-form";

import { theme } from "src/utils/ui/theme";

import { SwitchField, TextInputField } from "src/components/Form";
import { Box, Divider, Flex } from "src/components/Layout";
import { SelectCard } from "src/components/Selectable";
import { Text } from "src/components/Typography";

import { CreateWellProps, useCreateWell } from "./CreateWellProvider";
import { WellComponentInfo, useWhitelistedWellComponents } from "./useWhitelistedWellComponents";

import { ERC20Token } from "@beanstalk/sdk";

type FormValues = CreateWellProps["liquidity"] & CreateWellProps["salt"];

const FormContent = () => {
  const { salt: cachedSalt, liquidity: cachedLiquidity } = useCreateWell();
  const methods = useForm<FormValues>({
    defaultValues: {
      usingSalt: cachedSalt.usingSalt,
      salt: cachedSalt.salt,
      seedingLiquidity: cachedLiquidity.seedingLiquidity,
      token1Amount: cachedLiquidity.token1Amount?.toString(),
      token2Amount: cachedLiquidity.token2Amount?.toString()
    }
  });

  const onSubmit = (data: FormValues) => {
    console.log(data);
  };

  return (
    <FormProvider {...methods}>
      <form onSubmit={methods.handleSubmit(onSubmit)}>
        <Flex $gap={2}>
          <LiquidityForm />
          <SaltForm />
        </Flex>
      </form>
    </FormProvider>
  );
};

const LiquidityForm = () => {
  const {
    functionAndPump,
    tokens: { token1, token2 }
  } = useCreateWell();
  const { control } = useFormContext<FormValues>();
  // const

  return (
    <Flex $gap={2}>
      <Flex $direction="row" $gap={1} $alignItems="center">
        <SwitchField control={control} name="usingSalt" />
        <Text $variant="xs" $weight="bold" $mb={-0.5}>
          Seed Well with initial liquidity
        </Text>
      </Flex>
    </Flex>
  );
};

const SaltForm = () => {
  const { control, register } = useFormContext<FormValues>();
  const seedingLiquidity = useWatch({ control, name: "seedingLiquidity" });

  return (
    <Flex $gap={2}>
      <Flex $direction="row" $gap={1} $alignItems="center">
        <SwitchField control={control} name="seedingLiquidity" />
        <Text $variant="xs" $weight="bold" $mb={-0.5}>
          Deploy Well with a Salt
        </Text>
      </Flex>
      {seedingLiquidity && <TextInputField placeholder="Input Salt" {...register("salt")} />}
    </Flex>
  );
};

const getSelectedCardComponentProps = (
  address: string,
  components: readonly WellComponentInfo[]
): { title: string; subtitle?: string } | undefined => {
  const component = components.find((c) => c.address.toLowerCase() === address.toLowerCase());

  return {
    title: component?.component.name ?? address,
    subtitle: component?.component.summary
  };
};

const WellCreatePreview = () => {
  const { wellImplementation, functionAndPump, wellNameAndSymbol, tokens } = useCreateWell();

  if (
    !wellImplementation ||
    !functionAndPump ||
    !wellNameAndSymbol ||
    !tokens.token1 ||
    !tokens.token2
  )
    return null;
  // TODO: add go back step here...

  return (
    <WellCreatePreviewInner
      wellFunctionAndPump={functionAndPump}
      wellImplementation={wellImplementation}
      wellNameAndSymbol={wellNameAndSymbol}
      tokens={{ token1: tokens.token1, token2: tokens.token2 }}
    />
  );
};

type WellCreatePreviewInnerProps = {
  wellImplementation: CreateWellProps["wellImplementation"];
  wellFunctionAndPump: CreateWellProps["wellFunctionAndPump"];
  wellNameAndSymbol: CreateWellProps["wellNameAndSymbol"];
  tokens: { token1: ERC20Token; token2: ERC20Token };
};

const WellCreatePreviewInner = ({
  wellImplementation: { wellImplementation },
  wellFunctionAndPump: { pump, wellFunction },
  wellNameAndSymbol: { name: wellName, symbol: wellSymbol },
  tokens: { token1, token2 }
}: WellCreatePreviewInnerProps) => {
  const components = useWhitelistedWellComponents();

  return (
    <Flex $gap={2}>
      {/* well implementation */}
      <Flex $gap={1}>
        <Text $variant="h3">Well Implementation</Text>
        <SelectedComponentCard
          {...getSelectedCardComponentProps(wellImplementation, components.wellImplementations)}
        />
      </Flex>
      {/* name & symbol */}
      <Flex $gap={1}>
        <Text $variant="h3">Well Name & Symbol</Text>
        <Text $variant="l" $color="text.secondary">
          Name:{" "}
          <Text as="span" $variant="l" $weight="semi-bold" $color="text.secondary">
            {wellName}
          </Text>
        </Text>
        <Text $variant="l" $color="text.secondary">
          Symbol:{" "}
          <Text as="span" $variant="l" $weight="semi-bold" $color="text.secondary">
            {wellSymbol}
          </Text>
        </Text>
      </Flex>
      {/* Tokens */}
      <Flex $gap={1}>
        <Text $variant="h3">Well Name & Symbol</Text>
        <InlineImgFlex>
          <img src={token1?.logo ?? ""} alt={token1?.name ?? ""} />
          <Text $variant="l">{token1?.symbol ?? ""}</Text>
        </InlineImgFlex>
        <InlineImgFlex>
          <img src={token2?.logo ?? ""} alt={token2?.name ?? ""} />
          <Text $variant="l">{token2?.symbol ?? ""}</Text>
        </InlineImgFlex>
      </Flex>
      {/* Pricing Function */}
      <Flex $gap={1}>
        <Text $variant="h3">Pricing Function</Text>
        <SelectedComponentCard
          {...getSelectedCardComponentProps(wellFunction, components.wellFunctions)}
        />
      </Flex>
      <Flex $gap={1}>
        <Text $variant="h3">Pumps</Text>
        <SelectedComponentCard {...getSelectedCardComponentProps(pump, components.pumps)} />
      </Flex>
    </Flex>
  );
};

export const CreateWellPreviewDeploy = () => {
  return (
    <Flex $fullWidth>
      <div>
        <Text $variant="h2">Preview Deployment</Text>
        <Subtitle>Review selections and deploy your Well.</Subtitle>
      </div>
      <Flex $mt={3}>
        <WellCreatePreview />
      </Flex>
      <Box $my={4}>
        <Divider />
      </Box>
      <FormContent />
    </Flex>
  );
};

const Subtitle = styled(Text).attrs({ $mt: 0.5 })`
  color: ${theme.colors.stone};
`;

// shared components
const SelectedComponentCard = ({ title, subtitle }: { title?: string; subtitle?: string }) => {
  if (!title && !subtitle) return null;

  return (
    <SelectCard selected={true}>
      <div>
        <Text $variant="xs" $weight="bold">
          {title}
        </Text>
        {subtitle ? (
          <Text $variant="xs" $color="text.secondary">
            {subtitle}
          </Text>
        ) : null}
      </div>
    </SelectCard>
  );
};

const InlineImgFlex = styled(Flex).attrs({
  $display: "inline-flex",
  $direction: "row",
  $gap: 0.5
})`
  img {
    width: 20px;
    height: 20px;
    max-width: 20px;
    max-height: 20px;
    min-width: 20px;
    min-height: 20px;
  }
`;
