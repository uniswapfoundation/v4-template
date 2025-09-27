import * as React from "react";
import { SVGProps } from "react";
const MinusIcon = (props: SVGProps<SVGSVGElement>) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    width={24}
    height={24}
    viewBox="0 0 24 24"
    fill="none"
    {...props}
  >
    <path fill="currentColor" d="M21 13.5H3v-2.7h18v2.7Z" />
  </svg>
);
export default MinusIcon;
