import * as React from "react";
import { SVGProps } from "react";
const DotsVerticalIcon = (props: SVGProps<SVGSVGElement>) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    width={24}
    height={24}
    viewBox="0 0 24 24"
    fill="none"
    {...props}
  >
    <path
      stroke="currentColor"
      strokeWidth={2}
      d="M11 3h2v2h-2V3ZM13 11h-2v2h2v-2ZM11 19h2v2h-2v-2Z"
    />
  </svg>
);
export default DotsVerticalIcon;
