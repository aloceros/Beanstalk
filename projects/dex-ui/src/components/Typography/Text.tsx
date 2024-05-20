import React, { HTMLAttributes, ElementType } from "react";
import styled from "styled-components";
import { getFontVariantStyles, getFontWeightStyles } from ".";
import { FontVariant, FontWeight } from "./types";
import { FontColor, getFontColorStyles } from "src/utils/ui/theme/colors";

export interface IText extends HTMLAttributes<HTMLElement> {
  variant?: FontVariant;
  weight?: FontWeight;
  className?: string;
  color?: FontColor;
  as?: ElementType;
}

export const Text = ({ variant = "s", weight = "normal", color = "black", as, className, ...rest }: IText) => {
  return <TextComponent $variant={variant} $weight={weight} as={as} className={className} $color={color} {...rest} />;
};

const TextComponent = styled.div<{ $variant: FontVariant; $weight?: FontWeight; $color?: FontColor }>`
  ${(props) => getFontVariantStyles(props.$variant)};
  ${(props) => props.$weight && getFontWeightStyles(props.$weight)};
  ${(props) => props.$color && getFontColorStyles(props.$color)};
`;
