import * as React from "react";
import { SVGProps } from "react";
const PlusIcon = (props: SVGProps<SVGSVGElement>) => (
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
      d="M13.35 10.8H21v2.7h-7.65v8.099h-2.7v-8.1H3v-2.7h7.65V3.6h2.7v7.2Z"
    />
  </svg>
);
export default PlusIcon;
