// COMS20001 - Game of Life

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"
#include <timer.h>

#define  IMHT 16                    // Image height (Should be divisible by WORKERS)
#define  IMWD 16                    // Image width  (Should be divisible by 8 (number of bits in uchar))
#define  WORKERS 8                  // Number of workers (from 2 to 8, all can handle 512x512)(Best: 8)

#define REALWIDTH (IMWD/8)          // Width of main matrix with bitwise packing

#define INFNAME     "test16.pgm"    // Input image path
#define OUTFNAME    "testout.pgm"   // Output image path

typedef unsigned char uchar;        // Using uchar as shorthand

on tile[0] : port p_scl = XS1_PORT_1E;  // Interface ports to orientation
on tile[0] : port p_sda = XS1_PORT_1F;

#define FXOS8700EQ_I2C_ADDR 0x1E  // Register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

on tile[0] : in port buttons = XS1_PORT_4E; // Port to access xCore-200 buttons
on tile[0] : out port leds = XS1_PORT_4F;   // Port to access xCore-200 LEDs

#define NO_LEDS             0X0000
#define GREEN_SEPARATE_LED  0x0001
#define GREEN_LED           0x0004
#define BLUE_LED            0x0002
#define RED_LED             0x0008

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
[[combinable]]
void dataInStream(char infname[], chanend c_out)
{

  while(1)
  {
      select
      {
          case c_out :> int a:
              if(a != 1) break;
              int res;
              uchar line[ IMWD ];
              printf( "DataInStream: Start...\n" );

              // Open PGM file
              res = _openinpgm( infname, IMWD, IMHT );
              if( res )
              {
                printf( "DataInStream: Error openening %s\n.", infname );
                return;
              }

              // Read image line-by-line and send byte by byte to channel c_out
              for( int y = 0; y < IMHT; y++ )
              {
                _readinline( line, IMWD );
                for( int x = 0; x < IMWD; x++ )
                {
                  c_out <: line[ x ];
                }
              }

              // Close PGM image file
              _closeinpgm();
              printf( "DataInStream: Done...\n" );

              c_out <: 1;
              break;
      }

  }

}

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
[[combinable]]
void dataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];

  while(1)
  {
      select
      {
          case c_in :> int from_distributor:
              if(from_distributor != 1) break;
              // Open PGM file
              printf( "DataOutStream: Start...\n" );
              res = _openoutpgm( outfname, IMWD, IMHT );
              if( res )
              {
                printf( "DataOutStream: Error opening %s\n.", outfname );
                return;
              }

              // Compile each line of the image and write the image line-by-line
              for( int y = 0; y < IMHT; y++ )
              {
                for( int x = 0; x < IMWD; x++ )
                {
                  c_in :> line[ x ];
                }
                _writeoutline( line, IMWD );
                printf( "DataOutStream: Line written to the file...\n" );
              }

              // Close the PGM image
              _closeoutpgm();
              printf( "DataOutStream: Done...\n" );
              c_in <: 1;
              break;
      }

  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Initialise and  read orientation
//  Send every change in tiltness through the channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist)
{
    i2c_regop_res_t result;
    char status_data = 0;
    int tilted = 0;

    // Configure FXOS8700EQ
    result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
    if (result != I2C_REGOP_SUCCESS)
    {
        printf("I2C write reg failed\n");
    }

    // Enable FXOS8700EQ
    result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
    if (result != I2C_REGOP_SUCCESS)
    {
        printf("I2C write reg failed\n");
    }

    // Probe the orientation x-axis forever
    while (1)
    {
        // Check until new orientation data is available
        do {
          status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
        } while (!status_data & 0x08);

        // Get new x-axis tilt value
        int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

        // If the board is now tilted, send to the distributor 1
        if (!tilted && (x>50 || x<-50))
        {
            toDist <: 1;
            tilted = 1 - tilted;
        }
        // If the board is no longer tilted, send to the distributor 0
        if(tilted && (x < 10 && x > -10))
        {
            toDist <: 0;
            tilted = 1 - tilted;
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Listens for button input and sends it to the distributor
//
/////////////////////////////////////////////////////////////////////////////////////////
void buttonListener(in port b, chanend c_buttons)
{
    int r;

    while (1)
    {
        b when pinseq(15)  :> r;    // Check that no button is pressed
        b when pinsneq(15) :> r;    // Check if some buttons are pressed
        if ((r==13) || (r==14))     // If either button is pressed
        {
            c_buttons <: r;         // Send button pattern to userAnt
        }
    }
    return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Listens for button input and sends it to the distributor
//
/////////////////////////////////////////////////////////////////////////////////////////
void changeLEDs(out port p, chanend c_distributor)
{
    int pattern;

    while(1)
    {
        c_distributor :> pattern;
        p <: pattern;
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Main timer thread, communicating with the
//  client and running concurrently with the helper thread
//
/////////////////////////////////////////////////////////////////////////////////////////
void mainTimerThread(chanend c_helper_timer, chanend c_timer)
{
    unsigned int startTime;
    unsigned int endTime;
    unsigned int nullifier;
    unsigned int numberOfOverflows;
    unsigned long long int resultingTime;
    int fromController;
    int fromHelperTimerThread;
    unsigned int period = 100000000;                    // Period of 1 second
    unsigned long long overflowSize = 4294967295 + 1;   // The length of one overflow

    // We initialize a timer and find the constant
    // which added to it would nullify it.
    // This is done to ensure that the two timer threads
    // overflow at the same time (they don't share the same timer).

    timer t;
    t :> startTime;
    nullifier  =  -startTime;
    startTime +=  nullifier;


    while (1)
    {
        select
        {
            case c_helper_timer :> fromHelperTimerThread:
                numberOfOverflows++;
                break;

            case c_timer :> fromController:
                if(fromController == 1)
                {
                    t :> startTime;
                    startTime += nullifier;
                    numberOfOverflows = 0;
                }
                else if(fromController == 2)
                {
                    t :> endTime;
                    endTime += nullifier;

                    resultingTime   =   overflowSize;
                    resultingTime  *=   numberOfOverflows;
                    resultingTime  +=   endTime;
                    resultingTime  -=   startTime;
                }
                else if(fromController == 3)
                {
                    // printf("Number of timer overflows  : %u\n", numberOfOverflows);
                    printf("Time passed (raw)     : %llu\n", resultingTime);
                    printf("Time passed (seconds) : %f\n", ((double)resultingTime/period));
                    c_timer <: 1;
                }
                break;
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Helper timer thread, which checks continuously for overflows of the timer
//
/////////////////////////////////////////////////////////////////////////////////////////
void helperTimerThread(chanend c_helper_timer)
{
    unsigned int startTime;
    unsigned int currentTime;
    unsigned int nullifier;

    // We initialize a timer and find the constant
    // which added to it would nullify it
    // This is done to ensure that the two timer threads
    // overflow at the same time (they don't share the same timer)

    timer t;
    t :> startTime;
    nullifier  =  -startTime;
    startTime +=  nullifier;

    // Every 0.1 seconds we check if the timer has overflowed
    while(1)
    {
        t :> currentTime;
        currentTime += nullifier;
        if(currentTime < startTime)
        {
            c_helper_timer <: 1;
        }
        startTime = currentTime;
        delay_milliseconds(100);
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Print matrix to the terminal
//
/////////////////////////////////////////////////////////////////////////////////////////
void printMatrix(chanend c_workers[WORKERS])
{
    printf("Matrix console printing starting.\n");
    uchar package;
    for(int worker = 0; worker < WORKERS; worker ++)
    {
        c_workers[worker] <: 3;
        for(int a=0;a<IMHT/WORKERS;a++)
        {
            for(int b=0;b<REALWIDTH;b++)
            {
                c_workers[worker] :> package;
                for(int count = 0; count < 8; count++) {
                    int bitValue = (package & (1 << count));
                    if(bitValue != 0) printf("1 ");
                    else printf("0 ");
                }
            }
            printf("\n");
        }
    }

    printf("\n");
    printf("Matrix console printing ended.\n");
}

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Count number of all live cells
//
/////////////////////////////////////////////////////////////////////////////////////////
int countLiveCells(chanend c_workers[WORKERS])
{
    int result = 0;
    uchar package;

    for(int worker = 0; worker < WORKERS; worker++)
    {
        c_workers[worker] <: 3; //Request workers to send everything
        for(int a = 0; a < IMHT/WORKERS; a++)
        {
            for(int b = 0; b < REALWIDTH; b++)
            {
                c_workers[worker] :> package;
                for(int count = 0; count < 8; count++) {
                    if( ( package & (1 << count) ) != 0) result++;
                }
            }
        }
    }

    return result;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Calculate next state of a cell based on the number of neighbours
//  and its current state
//
/////////////////////////////////////////////////////////////////////////////////////////
char isAlive(int neighbours, char previousState)
{
    if(neighbours == 3)                         return 1;
    if(neighbours == 2 && previousState == 1)   return 1;
    return 0;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Calculate next state
//
/////////////////////////////////////////////////////////////////////////////////////////
void calculateNextState(uchar matrix[IMHT/WORKERS+2][REALWIDTH])
{
    //Two arrays used to save rows before updating them in the matrix
    //saved1 is used for rows with odd index
    //saved2 is used for rows with even index
    uchar saved1[REALWIDTH];
    uchar saved2[REALWIDTH];

    int height = IMHT/WORKERS+2;
    int width  = REALWIDTH;
    const int neighbourX[8] = {-1,  0, 1, -1, 1, -1,  0, 1};
    const int neighbourY[8] = {-1, -1, -1, 0, 0, 1, 1, 1};
    int numberOfAlive;
    int nX;
    int nY;

    for(int a = 1; a < height-1; a++)
    {
        //If applicable, save row with index (a-2), as it will not have impact on any rows from a to (height-2)
        if(a > 2) {
            if(a%2 == 1) {
                for(int b = 0; b < width; b++) matrix[a-2][b] = saved1[b];
            } else {
                for(int b = 0; b < width; b++) matrix[a-2][b] = saved2[b];
            }
        }
        if(a%2 == 1) { //If a is odd, save next state of the row a to saved1
            for(int b = 0; b < width; b++)
            {
                saved1[b] = 0;

                for(int c=0; c<8;c++)
                {
                    numberOfAlive = 0;
                    for(int i=0;i<8;i++)
                    {
                        nX = ((b*8)+neighbourX[i]+(8*width)+c)%(8*width);
                        nY = (a+neighbourY[i]+height)%height;
                        if((matrix[nY][nX/8] & (1 << (nX%8))) !=0) numberOfAlive++;
                    }
                    int cellValue = (matrix[a][b] >> c) & 1;
                    if (isAlive(numberOfAlive, cellValue))
                        saved1[b] = saved1[b] | (1 << c);
                }
            }
        } else { // a is even, save next state of the row a to saved2
            for(int b = 0; b < width; b++)
            {
                saved2[b] = 0;

                for(int c=0; c<8;c++)
                {
                    numberOfAlive = 0;
                    for(int i=0;i<8;i++)
                    {
                        nX = ((b*8)+neighbourX[i]+(8*width)+c)%(8*width);
                        nY = (a+neighbourY[i]+height)%height;
                        if((matrix[nY][nX/8] & (1 << (nX%8))) !=0) numberOfAlive++;
                    }
                    int cellValue = (matrix[a][b] >> c) & 1;
                    if (isAlive(numberOfAlive, cellValue))
                        saved2[b] = saved2[b] | (1 << c);
                }
            }
        }
    }
    //Save last two rows to the matrix (as they were not saved in previous 'for' loop)
    for(int b = 0; b < width; b++) {
        matrix[ (height-2) - (height-1)%2 ][b] = saved1[b];
        matrix[ (height-2) - height%2][b] = saved2[b];
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Worker thread working on part of the game state
//
/////////////////////////////////////////////////////////////////////////////////////////
void workerThread(chanend c_distributor)
{
    // Number of useful rows (without the duplicate on top and bottom) for each worker thread
    const int rowsPerWorker     = IMHT/WORKERS;

    uchar matrix[IMHT/WORKERS+2][REALWIDTH];

    while(1)
    {
        select
        {
            case c_distributor :> int fromDistributor:
                if(fromDistributor == 1)
                {
                    // Receiving matrix without additional columns
                    for(int b=0;b<rowsPerWorker;b++)    // For every row that should be received from the distributor
                    {
                        for(int c=0;c<REALWIDTH;c++)    // For every cell of every row we have to send every worker
                        {
                            c_distributor :> matrix[b+1][c];
                        }
                    }
                }
                else if(fromDistributor == 2)
                {
                    // Receiving additional row on top to each thread
                    for(int c=0;c<REALWIDTH;c++)    // For every cell of the upper row we must receive
                    {
                        c_distributor :> matrix[0][c];
                    }

                    // Receiving additional row on bottom to each thread
                    for(int c=0;c<REALWIDTH;c++)    // For every cell of the lower row we must send to every thread
                    {
                        c_distributor :> matrix[rowsPerWorker+1][c];
                    }

                    // Calculating next state
                    calculateNextState(matrix);

                    // Sending additional row on top to each thread
                    for(int c=0;c<REALWIDTH;c++)    // For every cell of the upper row we must send to every thread
                    {
                        c_distributor <: matrix[1][c];
                    }


                    // Sending additional row on bottom to each thread
                    for(int c=0;c<REALWIDTH;c++)    // For every cell of the lower row we must send to every thread
                    {
                        c_distributor <: matrix[rowsPerWorker][c];
                    }

                }
                else if(fromDistributor == 3)
                {
                    // Sending everything back
                    for(int b=0;b<rowsPerWorker;b++)    // For every row that should be sent to each worker
                    {
                        for(int c=0;c<REALWIDTH;c++)    // For every cell of every row we have to send every worker
                        {
                            c_distributor <: matrix[b+1][c];
                        }
                    }
                }
                break;
        }

    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Function, which implements game of life by farming out parts of the gamestate
//  to worker threads which implement it.
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend c_control, chanend c_timer, chanend c_buttons, chanend c_leds, chanend c_workers[WORKERS])
{
  uchar val;
  int   buttonInput;
  char  greenLedState = 1;
  char  matrix[WORKERS][2][REALWIDTH];   // Array for the additional rows (0 - top, 1 - bottom)
  int   rounds = 0;                                 // Number of passed rounds

  // Number of useful rows (without the duplicate on top and bottom) for each worker thread
  const int rowsPerWorker = IMHT/WORKERS;

  // Starting up and wait for pressing of SW1 button
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for press of SW1 button...\n" );

  while(1)
  {
      c_buttons :> buttonInput;
      if(buttonInput == 14) break;
  }

  //Read the input file
  uchar mask = 0;
  c_leds <: GREEN_LED;
  c_in <: 1;
  for(int worker = 0; worker < WORKERS; worker ++)  // For every worker
  {
      c_workers[worker] <: 1;
      for( int y = 0; y < rowsPerWorker; y++ )      // For every line for every worker
      {
          for( int x = 0; x < REALWIDTH; x++ )      // Go through each pixel per line
          {
              mask = 0;
              for(int count = 0; count < 8; count++) {
                  c_in :> val;
                  if(val) mask |= (1 << count);
              }
              c_workers[worker] <: mask;    //Send mask to the applicable worker
              //If this row is an additional row for other worker, save it
              if(y == 0) matrix[(worker+(WORKERS-1))%WORKERS][1][x] = mask;
              else if(y == rowsPerWorker-1) matrix[(worker+1)%WORKERS][0][x] = mask;
          }
      }
  }

  c_in :> int a;
  c_leds <: NO_LEDS;

  printf( "Processing...\n" );

  c_timer <: 1;

  uchar toPrint;
  while(1)
  {
      select
      {
          case c_buttons :> buttonInput:
              if(buttonInput == 13)
              {
                  printf("Processing stopped.\n");
                  printf( "Saving to file... \n" );
                  c_leds  <: BLUE_LED;
                  c_out <: 1;

                  for (int worker = 0; worker < WORKERS; worker ++)
                  {
                      c_workers[worker] <: 3;           // Sending a request to send everything
                      for(int b=0;b<rowsPerWorker;b++)  // For every row that we must receive from the worker
                      {
                          for(int c=0;c<REALWIDTH;c++)  // For every cell that we must receive from the worker
                          {
                              c_workers[worker] :> toPrint;
                              for(int count = 0; count < 8; count++) {
                                  if( (toPrint & (1 << count)) != 0) c_out <: ((uchar)(0xFF));
                                  else c_out <: ((uchar)(0x00));
                              }
                          }
                      }
                  }

                  c_leds  <: NO_LEDS;
                  c_out :> int a;
                  printf("Processing restarted.\n");
              }
              break;
          case c_control :> int value:
              if(value == 1)
              {
                  c_timer   <: 2;
                  c_leds      <: RED_LED;
                  printf("============================================\n");
                  printf("Number of rounds      : %d\n", rounds);
                  printf("Number of live cells  : %d\n", countLiveCells(c_workers));
                  c_timer <: 3;
                  c_timer :> int a;
                  printf("============================================\n");

                  c_control :> value;
                  c_leds      <: NO_LEDS;

                  printf("Processing restarted.\n");
              }
              break;

          default:
              // Sending parts of the matrix to each worker thread
              for (int worker = 0; worker < WORKERS; worker ++)
              {
                  c_workers[worker] <: 2;       // Sending information that additional rows will be sent
                  // Sending additional row on top to each thread
                  for(int c=0;c<REALWIDTH;c++)  // For every cell of the upper row we must send to every thread
                  {
                      c_workers[worker] <: matrix[worker][0][c];
                  }

                  // Sending additional row on bottom to each thread
                  for(int c=0;c<REALWIDTH;c++)  // For every cell of the lower row we must send to every thread
                  {
                      c_workers[worker] <: matrix[worker][1][c];
                  }
              }

              // Receiving from workers
              for (int worker = 0; worker < WORKERS; worker ++) // For every worker
              {
                  // Receiving additional row on top to each thread
                  for(int c=0;c<REALWIDTH;c++)      // For every cell of the upper row we must send to every thread
                  {
                      c_workers[worker] :> matrix[(worker+(WORKERS-1))%WORKERS][1][c];
                  }
                  // Receiving additional row on bottom to each thread
                  for(int c=0;c<REALWIDTH;c++)      // For every cell of the lower row we must send to every thread
                  {
                      c_workers[worker] :> matrix[(worker+1)%WORKERS][0][c];
                  }
              }


              rounds++;
              if(greenLedState)
              {
                  c_leds <: GREEN_SEPARATE_LED;
              }
              else
              {
                  c_leds <: NO_LEDS;
              }
              greenLedState = 1 - greenLedState;
              break;
      }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
//  Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void)
{
    i2c_master_if i2c[1];               // Interface to orientation

    chan c_inIO;                        // Channel for input file stream
    chan c_outIO;                       // Channel for output file stream
    chan c_control;                     // Channel for accelerometer
    chan c_timer;                       // Channel for main timer
    chan c_helper_timer;                // Channel for helper timer thread
    chan c_buttons;                     // Channel for buttons listener thread
    chan c_leds;                        // Channel for the led changing thread
    chan c_worker[8];                   // Channels for the four worker threads

    par
    {
        on tile[0] : i2c_master(i2c, 1, p_scl, p_sda, 10);          // Server thread providing orientation data
        on tile[0] : orientation(i2c[0],c_control);                 // Client thread reading orientation data
        on tile[0] : buttonListener(buttons, c_buttons);            // Thread listening for button action
        on tile[0] : changeLEDs(leds, c_leds);                      // Thread changing the leds
        on tile[0] : if(WORKERS >= 1) {workerThread(c_worker[0]);}  // Worker thread
        on tile[0] : if(WORKERS >= 3) {workerThread(c_worker[2]);}  // Worker thread
        on tile[0] : if(WORKERS >= 5) {workerThread(c_worker[4]);}  // Worker thread
        on tile[0] : if(WORKERS >= 7) {workerThread(c_worker[6]);}  // Worker thread

        on tile[1].core[0] : dataInStream(INFNAME, c_inIO);         // Thread to read in a PGM image
        on tile[1].core[0] : dataOutStream(OUTFNAME, c_outIO);      // Thread to write out a PGM image
        on tile[1] : mainTimerThread(c_helper_timer, c_timer);      // Main timer thread
        on tile[1] : helperTimerThread(c_helper_timer);             // Thread checking for timer overflow
        // Thread to coordinate work on image
        on tile[1] : distributor(c_inIO, c_outIO, c_control, c_timer, c_buttons, c_leds, c_worker);
        on tile[1] : if(WORKERS >= 2) {workerThread(c_worker[1]);}  // Worker thread
        on tile[1] : if(WORKERS >= 4) {workerThread(c_worker[3]);}  // Worker thread
        on tile[1] : if(WORKERS >= 6) {workerThread(c_worker[5]);}  // Worker thread
        on tile[1] : if(WORKERS >= 8) {workerThread(c_worker[7]);}  // Worker thread

      }

      return 0;
}
