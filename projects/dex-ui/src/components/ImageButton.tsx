import React, { JSXElementConstructor } from "react";

import styled from "styled-components";

import { FC } from "src/types";

type Props = {
  size?: number;
  alt: string;
  padding?: string;
  onClick: React.MouseEventHandler<HTMLButtonElement>;
  rotate?: string;
  margin?: string;
  color?: string;
} & ({ src: string; component?: never } | { src?: never; component?: JSXElementConstructor<any> });

type StyleProps = {
  padding?: string;
  rotate?: string;
  margin?: string;
};

// This component supports accepting either an imagine in two ways:
// -- as a string url via `src`
// -- as an SVG component via `component`. See src/components/Icons.tsx
// for acceptable components
export const ImageButton: FC<Props> = ({
  size = 32,
  src,
  component,
  alt = "Image",
  onClick,
  padding,
  rotate,
  margin,
  color
}) => {
  return (
    <Button onClick={onClick} padding={padding} rotate={rotate} margin={margin}>
      {src && <img src={src} alt={alt} width={size} />}
      {component &&
        React.createElement(component, { width: size, height: size, color: color || "#000" })}
    </Button>
  );
};

const Button = styled.button<StyleProps>`
  display: flex;
  justify-content: center;
  align-items: center;
  border: none;
  outline: none;
  background: none;
  padding: ${(props) => props.padding ?? "5px"};
  ${(props) => props.onClick && "cursor: pointer;"};
  rotate: ${(props) => props.rotate ?? "0"}deg;
  margin: ${(props) => props.margin ?? "0px"};
  transition-duration: 0.2s;
`;
