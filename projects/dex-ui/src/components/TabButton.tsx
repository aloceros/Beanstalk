import styled from "styled-components";

import { size } from "src/breakpoints";

import { BodyXS } from "./Typography";

export const TabButton = styled.button<{
  active?: boolean;
  stretch?: boolean;
  bold?: boolean;
  justify?: boolean;
  hover?: boolean;
  zIndex?: number;
}>`
  display: flex;
  flex-direction: row;
  gap: 8px;
  height: 48px;
  border: none;
  box-sizing: border-box;
  align-items: center;
  ${({ justify }) => justify && `justify-content: center;`}
  padding: 16px 16px;
  ${({ stretch }) => stretch && `width: 100%;`}
  font-weight: ${({ bold, active }) => (bold || active ? "600" : "normal")};
  z-index: ${({ active }) => (active ? "4" : "3")};
  outline: 0.5px solid ${({ active }) => (active ? "#000" : "#9CA3AF")};
  outline-offset: -0.5px;
  background-color: ${({ active }) => (active ? "#fff" : "#F9F8F6")};
  cursor: pointer;
  z-index: ${({ zIndex }) => zIndex || 0};

  ${({ hover }) =>
    hover &&
    `:hover {
      background-color: #f0fdf4;
    };`}

  @media (max-width: ${size.mobile}) {
    ${BodyXS}
    height: 48px;
    font-weight: ${({ bold, active }) => (bold || active ? "600" : "normal")};
    padding: 8px 8px;
    line-height: 18px;
  }
`;
