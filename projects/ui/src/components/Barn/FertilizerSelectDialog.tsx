import React from 'react';
import { Dialog, DialogProps } from '@mui/material';
import { FC } from '~/types';
import { StyledDialogContent, StyledDialogTitle } from '../Common/Dialog';
import EmptyState from '../Common/ZeroState/EmptyState';
import FertilizerSelect from '../Common/Form/FertilizerSelect';

export interface PlotSelectDialogProps {
  /** Closes dialog */
  handleClose: any;
  /** A farmer's fertilizers */
  fertilizers: any[];
}

const FertilizerSelectDialog: FC<PlotSelectDialogProps & DialogProps> = ({
  // Custom
  handleClose,
  fertilizers,
  // Dialog
  open,
}) => (
    <Dialog onClose={handleClose} open={open} fullWidth>
      <StyledDialogTitle onClose={handleClose}>My Fertilizer</StyledDialogTitle>
      <StyledDialogContent
        sx={{
          pb: 1, // enforces 10px padding around all
        }}
      >
        {fertilizers.length > 0 ? (
          <FertilizerSelect
            fertilizers={fertilizers}
          />
        ) : (
          <EmptyState message="You have no Fertilizer." />
        )}
      </StyledDialogContent>
    </Dialog>
  );

export default FertilizerSelectDialog;
