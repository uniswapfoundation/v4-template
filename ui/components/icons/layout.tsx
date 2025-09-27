import * as React from "react";
import { SVGProps } from "react";
const LayoutLeftIcon = (props: SVGProps<SVGSVGElement>) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    width={24}
    height={24}
    viewBox="0 0 24 24"
    fill="none"
    {...props}
  >
    <path
      fill="currentColor"
      d="M4 20H3v1h1v-1Zm16 0v1h1v-1h-1Zm0-16h1V3h-1v1ZM4 4V3H3v1h1Zm0 16v1h16v-2H4v1Zm16 0h1V4h-2v16h1Zm0-16V3H4v2h16V4ZM4 4H3v16h2V4H4Z"
    />
    <path
      fill="currentColor"
      d="M11 4V3H9v1h2ZM9 20v1h2v-1H9Zm1-16H9v16h2V4h-1Z"
    />
  </svg>
);
export default LayoutLeftIcon;
